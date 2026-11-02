import '../../core/models/agent/agent_coverage.dart';
import 'tag_block_integrity.dart';

class CoverageParseResult {
  const CoverageParseResult({this.review, this.errors = const <String>[]});

  final AgentCoverageReview? review;
  final List<String> errors;
}

const _coverageBlockTags = <String>{
  'COVERAGE',
  'MISSING',
  'DUPLICATE',
  'NOTES',
};

final _coverageBlockPattern = RegExp(
  r'\[COVERAGE\b([^\]]*)\]([\s\S]*?)\[/COVERAGE\]',
  caseSensitive: false,
);
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
final _sourceRefPattern = RegExp(r'^(t\d+|p\d+|src-\d+)$');

/// Reports unbalanced or mis-nested coverage blocks. Parsing is reported as
/// failed when this returns anything, so the caller can request one repair.
List<String> coverageTagIntegrityErrors(String raw) {
  final errors = <String>[
    ...tagBlockIntegrityErrors(
      raw,
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
  final blocks = _coverageBlockPattern.allMatches(raw).length;
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
}) {
  final errors = <String>[...coverageTagIntegrityErrors(raw)];
  final blocks = _coverageBlockPattern.allMatches(raw).toList(growable: false);
  if (blocks.length != 1) {
    return CoverageParseResult(errors: _unique(errors));
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
  for (final match in _missingPattern.allMatches(body)) {
    final itemAttrs = match.group(1) ?? '';
    final kindValue = _attr(itemAttrs, 'kind').toLowerCase();
    AgentCoverageKind? kind;
    for (final value in AgentCoverageKind.values) {
      if (value.wireName == kindValue) {
        kind = value;
        break;
      }
    }
    if (kind == null) {
      errors.add('MISSING kind 无效');
      continue;
    }
    final query = _attr(itemAttrs, 'query').trim();
    if (query.isEmpty || query.length > 100) {
      errors.add('MISSING query 长度无效');
      continue;
    }
    final refs = _listAttr(itemAttrs, 'refs');
    if (refs.isEmpty ||
        refs.length > 8 ||
        refs.any((ref) => !_sourceRefPattern.hasMatch(ref))) {
      errors.add('MISSING refs 无效');
      continue;
    }
    final reason = (match.group(2) ?? '').trim();
    if (reason.isEmpty || reason.length > 500) {
      errors.add('MISSING reason 长度无效');
      continue;
    }
    final priorityValue = _attr(itemAttrs, 'priority');
    final priority = priorityValue.isEmpty ? 3 : int.tryParse(priorityValue);
    if (priority == null || priority < 1 || priority > 5) {
      errors.add('MISSING priority 无效');
      continue;
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

  final duplicateGroups = <AgentCoverageDuplicateGroup>[];
  for (final match in _duplicatePattern.allMatches(body)) {
    final itemAttrs = match.group(1) ?? '';
    final dictionaryId = _attrAny(itemAttrs, const <String>[
      'dictionary',
      'dictionary_id',
    ]);
    final keep = _attrAny(itemAttrs, const <String>['keep', 'keep_entry_key']);
    final remove = _listAttrAny(itemAttrs, const <String>[
      'remove',
      'remove_entry_keys',
    ]);
    final reason = (match.group(2) ?? '').trim();
    if (dictionaryId.isEmpty ||
        keep.isEmpty ||
        remove.isEmpty ||
        reason.isEmpty) {
      errors.add('DUPLICATE 字段无效');
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

  final notes = _notesPattern.firstMatch(body)?.group(1)?.trim() ?? '';
  if (verdict == AgentCoverageVerdict.sufficient &&
      (missing.isNotEmpty || duplicateGroups.isNotEmpty)) {
    errors.add('verdict=sufficient 时不得返回 MISSING/DUPLICATE');
  }
  if (errors.isNotEmpty) {
    return CoverageParseResult(errors: _unique(errors));
  }
  return CoverageParseResult(
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
