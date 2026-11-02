import '../../core/models/agent/agent_coverage.dart';
import 'tag_block_integrity.dart';

typedef CoverageDebugLog = void Function(String message);

class CoverageParseResult {
  const CoverageParseResult({
    this.review,
    this.errors = const <String>[],
    this.normalizedText = '',
  });

  final AgentCoverageReview? review;
  final List<String> errors;

  /// The text actually parsed, after safe tag normalization. A repair request
  /// must use this instead of the raw response so it cannot repeat a structural
  /// error that normalization already fixed.
  final String normalizedText;
}

const _coverageBlockTags = <String>{
  'COVERAGE',
  'MISSING',
  'DUPLICATE',
  'NOTES',
};

const _kindAliases = <String, AgentCoverageKind>{
  'word': AgentCoverageKind.word,
  'vocabulary': AgentCoverageKind.word,
  'term': AgentCoverageKind.word,
  'grammar': AgentCoverageKind.grammar,
  'grammar_pattern': AgentCoverageKind.grammar,
  'sense': AgentCoverageKind.sense,
  'meaning': AgentCoverageKind.sense,
  'usage': AgentCoverageKind.usage,
  'translation': AgentCoverageKind.usage,
  'reading': AgentCoverageKind.reading,
  'pronunciation': AgentCoverageKind.reading,
  'example': AgentCoverageKind.example,
  'example_sentence': AgentCoverageKind.example,
  'context': AgentCoverageKind.context,
};

final _coverageBlockPattern = RegExp(
  r'\[COVERAGE\b([^\]]*)\]([\s\S]*?)\[/COVERAGE\]',
  caseSensitive: false,
);
final _coverageOpenPattern = RegExp(
  r'\[COVERAGE\b([^\]]*)\]',
  caseSensitive: false,
);
final _coverageClosePattern = RegExp(r'\[/COVERAGE\]', caseSensitive: false);
final _missingPattern = RegExp(
  r'\[MISSING\b([^\]]*)\]([\s\S]*?)\[/MISSING\]',
  caseSensitive: false,
);
final _duplicatePattern = RegExp(
  r'\[DUPLICATE\b([^\]]*)\]([\s\S]*?)\[/DUPLICATE\]',
  caseSensitive: false,
);
final _notesPattern = RegExp(
  r'\[NOTES\]([\s\S]*?)\[/NOTES\]',
  caseSensitive: false,
);
final _childBlockPattern = RegExp(
  r'\[(?:/?)(MISSING|DUPLICATE|NOTES)\b',
  caseSensitive: false,
);

/// Models often return a single empty `[COVERAGE verdict="sufficient"]` tag
/// (or a self-closing tag) instead of the paired block. That response is
/// unambiguous and safe; normalize it before integrity checking instead of
/// spending a repair call and then showing "coverage unavailable".
///
/// This function is idempotent: normalizing an already normalized response
/// returns it unchanged.
String normalizeCoverageResponseText(String raw) => _normalizeCoverageTags(raw);

String _normalizeCoverageTags(String raw) {
  var text = raw.replaceAll('\r\n', '\n');
  text = text.replaceAll(
    RegExp(r'^\s*```[A-Za-z0-9_-]*\s*$', multiLine: true),
    '',
  );
  text = text.replaceAll('```', '');
  final opens = _coverageOpenPattern.allMatches(text).toList(growable: false);
  final closes = _coverageClosePattern.allMatches(text).length;
  if (opens.length != 1 || closes != 0) return text;
  final open = opens.single;
  final after = text.substring(open.end);
  if (_childBlockPattern.hasMatch(after)) return text;
  var attrs = open.group(1) ?? '';
  if (RegExp(r'/\s*$').hasMatch(attrs)) {
    attrs = attrs.replaceFirst(RegExp(r'/\s*$'), '');
    final openTag = '[COVERAGE$attrs]';
    text = text.replaceRange(open.start, open.end, openTag);
    final insertAt = open.start + openTag.length;
    return '${text.substring(0, insertAt)}[/COVERAGE]'
        '${text.substring(insertAt)}';
  }
  final insertAt = open.end;
  return '${text.substring(0, insertAt)}[/COVERAGE]'
      '${text.substring(insertAt)}';
}

/// Reports unbalanced or mis-nested coverage blocks. Parsing is reported as
/// failed when this returns anything, so the caller can request one repair.
List<String> coverageTagIntegrityErrors(String raw) {
  final normalized = normalizeCoverageResponseText(raw);
  final errors = <String>[
    ...tagBlockIntegrityErrors(
      normalized,
      blockTags: _coverageBlockTags,
      rootOnlyTags: const <String>{'COVERAGE'},
      requiredParent: const <String, String>{
        'MISSING': 'COVERAGE',
        'DUPLICATE': 'COVERAGE',
        'NOTES': 'COVERAGE',
      },
      singleInParent: const <String>{'NOTES'},
    ),
  ];
  final blocks = _coverageBlockPattern.allMatches(normalized).length;
  if (blocks == 0) {
    errors.add('缺少 [COVERAGE] 块');
  } else if (blocks > 1) {
    errors.add('必须且只能有一个 [COVERAGE] 块');
  }
  return List<String>.unmodifiable(errors.toSet());
}

CoverageParseResult parseCoverageReview(
  String raw, {
  required String expectedSourceId,
  CoverageDebugLog? debugLog,
}) {
  final normalized = normalizeCoverageResponseText(raw);
  void note(String message) => debugLog?.call(message);
  final errors = <String>[...coverageTagIntegrityErrors(normalized)];
  final blocks = _coverageBlockPattern
      .allMatches(normalized)
      .toList(growable: false);
  if (blocks.length != 1) {
    return CoverageParseResult(
      errors: _unique(errors),
      normalizedText: normalized,
    );
  }

  final block = blocks.single;
  final attrs = block.group(1) ?? '';
  final body = block.group(2) ?? '';
  final verdictValue = _attr(attrs, 'verdict').toLowerCase();
  final verdict = switch (verdictValue) {
    'sufficient' => AgentCoverageVerdict.sufficient,
    'missing' => AgentCoverageVerdict.missing,
    _ => null,
  };
  if (verdict == null) {
    errors.add('COVERAGE verdict 必须为 sufficient 或 missing');
  }

  final missing = <AgentCoverageMissing>[];
  if (verdict == AgentCoverageVerdict.missing) {
    var itemIndex = 0;
    for (final match in _missingPattern.allMatches(body)) {
      final index = itemIndex++;
      final itemAttrs = match.group(1) ?? '';
      final kindValue = _attr(itemAttrs, 'kind').toLowerCase();
      final kind =
          _kindAliases[kindValue] ?? AgentCoverageKind.fromWire(kindValue);
      if (kindValue != kind.wireName) {
        note(
          'normalized MISSING[$index] kind="${_logValue(kindValue)}" '
          '-> "${kind.wireName}"',
        );
      }
      final query = _attr(itemAttrs, 'query').trim();
      if (query.isEmpty || query.length > 100) {
        note(
          'dropped MISSING[$index] query="${_logValue(query)}" '
          '(chars=${query.length})',
        );
        continue;
      }
      final rawRefs = _listAttr(itemAttrs, 'refs');
      // Models sometimes confuse a citation id (`source-1`) with a source id.
      // With one primary source, map it back instead of discarding the item.
      final refs = <String>[];
      for (final ref in rawRefs) {
        if (RegExp(r'^source-\d+$').hasMatch(ref) &&
            expectedSourceId.isNotEmpty) {
          note(
            'normalized MISSING[$index] ref="$ref" -> '
            '"$expectedSourceId"',
          );
          refs.add(expectedSourceId);
        } else {
          refs.add(ref);
        }
      }
      if (refs.isEmpty || refs.length > 8) {
        note(
          'dropped MISSING[$index] refs="${_logValue(rawRefs.join(','))}" '
          '(count=${refs.length})',
        );
        continue;
      }
      var reason = (match.group(2) ?? '').trim();
      if (reason.length > 500) {
        note(
          'truncated MISSING[$index] reason '
          'chars=${reason.length} -> 500',
        );
        reason = reason.substring(0, 500);
      }
      final priorityValue = _attr(itemAttrs, 'priority');
      final parsedPriority = priorityValue.isEmpty
          ? 3
          : int.tryParse(priorityValue);
      final priority = (parsedPriority ?? 3).clamp(1, 5);
      if (priorityValue.isNotEmpty &&
          (parsedPriority == null || parsedPriority != priority)) {
        note(
          'normalized MISSING[$index] '
          'priority="${_logValue(priorityValue)}" -> $priority',
        );
      }
      missing.add(
        AgentCoverageMissing(
          kind: kind,
          query: query,
          sourceRefs: refs,
          reason: reason,
          priority: priority,
        ),
      );
    }
  }

  final duplicateGroups = <AgentCoverageDuplicateGroup>[];
  if (verdict == AgentCoverageVerdict.missing) {
    var itemIndex = 0;
    for (final match in _duplicatePattern.allMatches(body)) {
      final index = itemIndex++;
      final itemAttrs = match.group(1) ?? '';
      final dictionaryId = _attrAny(itemAttrs, const <String>[
        'dictionary',
        'dictionary_id',
      ]);
      final keep = _attrAny(itemAttrs, const <String>[
        'keep',
        'keep_entry_key',
      ]);
      final remove = _listAttrAny(itemAttrs, const <String>[
        'remove',
        'remove_entry_keys',
      ]);
      var reason = (match.group(2) ?? '').trim();
      if (reason.length > 500) {
        note(
          'truncated DUPLICATE[$index] reason '
          'chars=${reason.length} -> 500',
        );
        reason = reason.substring(0, 500);
      }
      // One malformed suggestion must not discard the whole review. The
      // orchestrator verifies every duplicate locally before removing
      // anything, so dropping this item is safe.
      if (dictionaryId.isEmpty || keep.isEmpty || remove.isEmpty) {
        note(
          'dropped DUPLICATE[$index] dictionary="${_logValue(dictionaryId)}" '
          'keep="${_logValue(keep)}" removeCount=${remove.length}',
        );
        continue;
      }
      duplicateGroups.add(
        AgentCoverageDuplicateGroup(
          dictionaryId: dictionaryId,
          keepEntryKey: keep,
          removeEntryKeys: remove,
          reason: reason,
        ),
      );
    }
  }

  final notes = _notesPattern.firstMatch(body)?.group(1)?.trim() ?? '';
  if (errors.isNotEmpty) {
    return CoverageParseResult(
      errors: _unique(errors),
      normalizedText: normalized,
    );
  }
  return CoverageParseResult(
    normalizedText: normalized,
    review: AgentCoverageReview(
      sourceId: expectedSourceId,
      verdict: verdict!,
      missing: List<AgentCoverageMissing>.unmodifiable(missing),
      duplicateGroups: List<AgentCoverageDuplicateGroup>.unmodifiable(
        duplicateGroups,
      ),
      notes: notes,
    ),
  );
}

List<String> _unique(List<String> values) =>
    List<String>.unmodifiable(values.toSet());

/// Debug-only value preview. It collapses whitespace and truncates so a
/// malformed model item cannot flood the log with prompt-sized content.
String _logValue(String value) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= 40) return singleLine;
  return '${singleLine.substring(0, 40)}…';
}

String _attrAny(String attrs, List<String> names) {
  for (final name in names) {
    final value = _attr(attrs, name);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _attr(String attrs, String name) {
  final pattern = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s]+))',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(attrs);
  if (match == null) return '';
  return (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim();
}

List<String> _listAttr(String attrs, String name) {
  return _splitRefs(_attr(attrs, name));
}

List<String> _listAttrAny(String attrs, List<String> names) {
  return _splitKeys(_attrAny(attrs, names));
}

List<String> _splitRefs(String value) {
  return <String>[
    for (final item in value.split(RegExp(r'[|｜,，\s]+')))
      if (item.trim().isNotEmpty) item.trim(),
  ];
}

List<String> _splitKeys(String value) {
  return <String>[
    for (final item in value.split(RegExp(r'[|｜,，]')))
      if (item.trim().isNotEmpty) item.trim(),
  ];
}
