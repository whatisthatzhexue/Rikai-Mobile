/// Structural checks for the flat tag protocol.
///
/// The regex parsers are intentionally forgiving so that one bad block does not
/// discard an otherwise usable answer. That also means a truncated or
/// mis-nested block can silently disappear. This validator reports those
/// structural problems so callers can request one format-correction pass
/// without re-running OCR or dictionary lookups.
List<String> tagBlockIntegrityErrors(
  String raw, {
  required Set<String> blockTags,
  Set<String> rootOnlyTags = const <String>{},
  Map<String, String> requiredParent = const <String, String>{},
  Set<String> singleInParent = const <String>{},
}) {
  final errors = <String>[];
  final stack = <_TagFrame>[];
  final tagPattern = RegExp(
    r'\[\s*(/?)\s*([A-Za-z][A-Za-z0-9_]*)\b[^\]]*\]',
    caseSensitive: false,
  );

  for (final match in tagPattern.allMatches(raw)) {
    final closing = (match.group(1) ?? '').isNotEmpty;
    final tag = (match.group(2) ?? '').toUpperCase();
    if (!blockTags.contains(tag)) continue;

    if (!closing) {
      final parent = stack.isEmpty ? null : stack.last.tag;
      if (rootOnlyTags.contains(tag) && parent != null) {
        errors.add('标签 [$tag] 只能位于顶层，不能嵌套在 [$parent] 内');
      }
      final expectedParent = requiredParent[tag];
      if (expectedParent != null && parent != expectedParent) {
        errors.add('标签 [$tag] 必须位于 [$expectedParent] 内');
      }
      if (parent != null &&
          singleInParent.contains(tag) &&
          stack.last.children.contains(tag)) {
        errors.add('标签 [$parent] 内出现重复的 [$tag]');
      }
      if (stack.isNotEmpty) stack.last.children.add(tag);
      stack.add(_TagFrame(tag));
      continue;
    }

    if (stack.isEmpty) {
      errors.add('多余的结束标签 [/$tag]');
      continue;
    }
    if (stack.last.tag == tag) {
      stack.removeLast();
      continue;
    }
    final matchingIndex = stack.lastIndexWhere((frame) => frame.tag == tag);
    if (matchingIndex < 0) {
      errors.add('多余的结束标签 [/$tag]');
      continue;
    }
    final unclosed = stack
        .sublist(matchingIndex + 1)
        .map((frame) => frame.tag)
        .join('、');
    errors.add('标签 [$tag] 的结束顺序不正确；[$unclosed] 尚未闭合');
    stack.removeRange(matchingIndex, stack.length);
  }

  for (final frame in stack.reversed) {
    errors.add('标签 [${frame.tag}] 缺少结束标签');
  }
  return List<String>.unmodifiable(errors.toSet());
}

class _TagFrame {
  _TagFrame(this.tag);

  final String tag;
  final Set<String> children = <String>{};
}
