/// Inline rich-text tags used only for display formatting.
///
/// The post-processing model may insert these tags but must never change the
/// base text. [stripRichTextTags] is the single source used by the diff guard
/// and by the renderer's tests.
final RegExp richTextTagPattern = RegExp(
  r'\[(RUBY=[^\]]*|/RUBY|BOLD|/BOLD|UNDERLINE|/UNDERLINE)\]',
  caseSensitive: false,
);

final RegExp _kanaReadingPattern = RegExp(r'^[ぁ-ゖァ-ヺー・]+$');

String stripRichTextTags(String text) =>
    text.replaceAll(richTextTagPattern, '');

/// True when every tag is paired, not nested, and RUBY readings are kana.
bool isWellFormedRichText(String text) {
  final stack = <String>[];
  for (final match in richTextTagPattern.allMatches(text)) {
    final raw = match.group(1) ?? '';
    final lower = raw.toLowerCase();
    if (lower.startsWith('ruby=')) {
      if (stack.isNotEmpty) return false;
      final reading = raw.substring('ruby='.length).trim();
      if (reading.isEmpty || !_kanaReadingPattern.hasMatch(reading)) {
        return false;
      }
      final close = text.indexOf('[/RUBY]', match.end);
      if (close < 0) return false;
      final base = text.substring(match.end, close);
      if (base.isEmpty || base.contains('\n') || base.contains('\r')) {
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
      if (stack.isNotEmpty) return false;
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
