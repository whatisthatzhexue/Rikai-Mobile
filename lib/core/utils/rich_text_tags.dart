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

/// RUBY pair plus an optional parenthetical reading immediately after it.
/// The post-processor often wraps an existing `surface（reading）` annotation
/// and leaves the original parentheses outside the pair.
final RegExp _rubyWithTrailingReadingPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]([（(][^（）()\r\n]*[）)])?',
  caseSensitive: false,
);

final RegExp _trailingReadingPattern = RegExp(r'[（(]([^（）()\r\n]*)[）)]$');
final RegExp _leadingReadingPattern = RegExp(r'^[（(]([^（）()\r\n]*)[）)]');

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

/// A Japanese word followed by a kana-only parenthetical reading, e.g.
/// `自分（じぶん）`. This is the display form used before RUBY tags are applied;
/// the result model is asked to emit YOMI instead, but local fallback still
/// needs to recognize the parenthetical form.
final RegExp _parentheticalReadingPattern = RegExp(
  r'([぀-ヿ㐀-䶿一-鿿々〆ヶー]{1,16})'
  r'([（(])'
  r'([぀-ゟ゠-ヿー]{1,24})'
  r'([）)])',
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

/// Converts `word（reading）` annotations to RUBY without touching existing
/// RUBY/YOMI spans. A reading identical to its base is dropped. This is a
/// display-only fallback: the base characters are never changed.
String parentheticalReadingsToRuby(String text) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in _protectedDisplaySpanPattern.allMatches(text)) {
    buffer.write(
      _convertParentheticalReadings(text.substring(cursor, match.start)),
    );
    buffer.write(match.group(0));
    cursor = match.end;
  }
  buffer.write(_convertParentheticalReadings(text.substring(cursor)));
  return buffer.toString();
}

String _convertParentheticalReadings(String text) {
  return text.replaceAllMapped(_parentheticalReadingPattern, (match) {
    final base = match.group(1) ?? '';
    final reading = cleanReading(match.group(3) ?? '');
    if (base.isEmpty || reading.isEmpty || reading == base) return base;
    return '[RUBY=$reading]$base[/RUBY]';
  });
}

/// Removes a parenthetical reading at the end of [base] when it is exactly the
/// reading already supplied by the RUBY tag. This prevents
/// `[RUBY=いま]今（いま）[/RUBY]` from rendering as `今（いま）（いま）`.
String rubyDisplayBase(String base, String reading) {
  final cleanedReading = cleanReading(reading);
  if (cleanedReading.isEmpty) return base;
  final match = _trailingReadingPattern.firstMatch(base);
  if (match == null) return base;
  if (cleanReading(match.group(1) ?? '') != cleanedReading) return base;
  return base.substring(0, match.start);
}

/// Returns the offset after a parenthetical reading that immediately follows
/// a RUBY span and duplicates its reading, for example
/// `[RUBY=いま]今[/RUBY]（いま）`. The duplicate parentheses are display-only
/// noise and must not be shown or copied twice.
int skipDuplicateRubyReading(String text, int offset, String reading) {
  final cleanedReading = cleanReading(reading);
  if (cleanedReading.isEmpty || offset >= text.length) return offset;
  final match = _leadingReadingPattern.firstMatch(text.substring(offset));
  if (match == null) return offset;
  if (cleanReading(match.group(1) ?? '') != cleanedReading) return offset;
  return offset + match.end;
}

String stripRichTextTags(String text) =>
    text.replaceAll(richTextTagPattern, '');

final RegExp _rubyThenYomiPattern = RegExp(
  r'\[RUBY=([^\]]*)\]([\s\S]*?)\[/RUBY\]\[YOMI\]([\s\S]*?)\[/YOMI\]',
  caseSensitive: false,
);

/// Removes a YOMI block immediately after a RUBY pair when both carry the
/// same reading. The formatter is told to delete the YOMI itself, but a
/// retained duplicate must never render/export as `RUBY + （reading）`.
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

/// Converts YOMI annotations to plain parenthetical readings for fallback
/// display. The result-generation model writes `word[YOMI]reading[/YOMI]`
/// without parentheses; a plain renderer needs `word（reading）`. Older output
/// that already contains parentheses is preserved. A YOMI block that
/// duplicates the reading of an immediately preceding RUBY pair is dropped.
String stripYomiTags(String text) {
  return _dropDuplicateYomiAfterRuby(text)
      .replaceAllMapped(yomiBlockPattern, (match) {
        final content = match.group(1) ?? '';
        final trimmed = content.trim();
        if (trimmed.isEmpty) return '';
        final alreadyParenthesized =
            (trimmed.startsWith('（') && trimmed.endsWith('）')) ||
            (trimmed.startsWith('(') && trimmed.endsWith(')'));
        return alreadyParenthesized ? content : '（$trimmed）';
      })
      .replaceAll(yomiTagPattern, '');
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
/// RUBY becomes `base（reading）`, BOLD/UNDERLINE tags disappear, and YOMI
/// wrappers are removed while their parenthetical reading is kept.
String richTextToPlain(String text) {
  var plain = _dropDuplicateYomiAfterRuby(text);
  plain = plain.replaceAllMapped(_rubyWithTrailingReadingPattern, (match) {
    final reading = cleanReading(match.group(1) ?? '');
    final base = match.group(2) ?? '';
    final trailing = match.group(3) ?? '';
    if (reading.isEmpty) return '$base$trailing';
    final displayBase = rubyDisplayBase(base, reading);
    if (displayBase.isEmpty) return '$base$trailing';
    // A parenthetical immediately after [/RUBY] is the same annotation when
    // its cleaned content equals the RUBY reading; keep at most one copy.
    final keepTrailing =
        trailing.isNotEmpty && cleanReading(trailing) != reading
        ? trailing
        : '';
    if (reading == displayBase) return '$displayBase$keepTrailing';
    return '$displayBase（$reading）$keepTrailing';
  });
  plain = plain.replaceAll(richTextTagPattern, '');
  return stripYomiTags(plain);
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
