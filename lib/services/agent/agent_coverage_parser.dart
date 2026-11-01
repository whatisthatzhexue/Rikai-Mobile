import 'dart:convert';

import '../../core/models/agent/agent_coverage.dart';

class CoverageParseResult {
  const CoverageParseResult({this.review, this.errors = const <String>[]});

  final AgentCoverageReview? review;
  final List<String> errors;
}

final _sourceRefPattern = RegExp(r'^(t\d+|p\d+|src-\d+)$');

CoverageParseResult parseCoverageReview(
  String raw, {
  required String expectedSourceId,
}) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return const CoverageParseResult(errors: <String>['没有 JSON 对象']);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } catch (error) {
    return CoverageParseResult(errors: <String>['JSON 无法解析', error.toString()]);
  }
  if (decoded is! Map) {
    return const CoverageParseResult(errors: <String>['JSON 顶层不是对象']);
  }
  final json = decoded.map((key, value) => MapEntry(key.toString(), value));
  final errors = <String>[];

  if (json['schema'] != AgentCoverageReview.schema) {
    errors.add('schema 必须为 ${AgentCoverageReview.schema}');
  }
  final sourceId = _text(json['source_id']);
  if (sourceId.isEmpty) {
    errors.add('source_id 不能为空');
  } else if (expectedSourceId.isNotEmpty && sourceId != expectedSourceId) {
    errors.add('source_id 与本次输入不一致');
  }
  final verdictValue = _text(json['verdict']);
  if (verdictValue != 'sufficient' && verdictValue != 'missing') {
    errors.add('verdict 必须为 sufficient 或 missing');
  }

  final missing = <AgentCoverageMissing>[];
  final rawMissing = json['missing'];
  if (rawMissing is! List) {
    errors.add('missing 必须是数组');
  } else {
    for (final item in rawMissing) {
      if (item is! Map) {
        errors.add('missing 项必须是对象');
        continue;
      }
      final value = item.map((key, item) => MapEntry(key.toString(), item));
      final kind = _text(value['kind']);
      if (!AgentCoverageKind.values.any((item) => item.wireName == kind)) {
        errors.add('missing.kind 无效');
        continue;
      }
      final query = _text(value['query']).trim();
      if (query.isEmpty || query.length > 100) {
        errors.add('missing.query 长度无效');
        continue;
      }
      final refs = _strings(value['source_refs']);
      if (refs.isEmpty ||
          refs.length > 8 ||
          refs.any((ref) => !_sourceRefPattern.hasMatch(ref))) {
        errors.add('missing.source_refs 无效');
        continue;
      }
      final reason = _text(value['reason']).trim();
      if (reason.isEmpty || reason.length > 500) {
        errors.add('missing.reason 长度无效');
        continue;
      }
      final priority = value['priority'];
      if (priority != null &&
          (priority is! num || priority < 1 || priority > 5)) {
        errors.add('missing.priority 无效');
        continue;
      }
      missing.add(
        AgentCoverageMissing(
          kind: AgentCoverageKind.fromWire(kind),
          query: query,
          sourceRefs: refs,
          reason: reason,
          priority: priority is num ? priority.toInt() : 3,
        ),
      );
    }
  }

  final duplicateGroups = <AgentCoverageDuplicateGroup>[];
  final rawGroups = json['duplicate_groups'];
  if (rawGroups is! List) {
    errors.add('duplicate_groups 必须是数组');
  } else {
    for (final item in rawGroups) {
      if (item is! Map) {
        errors.add('duplicate_groups 项必须是对象');
        continue;
      }
      final value = item.map((key, item) => MapEntry(key.toString(), item));
      final dictionaryId = _text(value['dictionary_id']).trim();
      final keep = _text(value['keep_entry_key']).trim();
      final remove = _strings(value['remove_entry_keys']);
      final reason = _text(value['reason']).trim();
      if (dictionaryId.isEmpty ||
          keep.isEmpty ||
          remove.isEmpty ||
          reason.isEmpty) {
        errors.add('duplicate_groups 字段无效');
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

  if (errors.isNotEmpty) return CoverageParseResult(errors: errors);
  return CoverageParseResult(
    review: AgentCoverageReview(
      sourceId: sourceId,
      verdict: AgentCoverageVerdict.fromWire(verdictValue),
      missing: List<AgentCoverageMissing>.unmodifiable(missing),
      duplicateGroups: List<AgentCoverageDuplicateGroup>.unmodifiable(
        duplicateGroups,
      ),
      notes: _text(json['notes']),
    ),
  );
}

String _text(Object? value) => value is String ? value : '';

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
