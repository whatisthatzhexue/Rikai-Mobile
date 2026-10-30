/// Lenient normalization of a model-produced analysis object.
///
/// Providers do not all follow the exact schema. This accepts a small set of
/// well-known aliases (camelCase, plural, "sentences") before the strict DTO
/// parser runs. It never invents content; it only renames keys and supplies the
/// fixed translation label.
Map<String, Object?> normalizeAnalysisJson(Map<String, Object?> json) {
  final result = <String, Object?>{...json};
  _alias(result, 'source_id', const <String>['sourceId', 'source']);
  _alias(result, 'translation', const <String>[
    'translations',
    'translated',
    'translation_text',
  ]);
  _alias(result, 'segments', const <String>['sentences', 'items']);
  _alias(result, 'interpretations', const <String>[
    'alternatives',
    'meanings',
  ]);
  _alias(result, 'unresolved', const <String>['unresolved_items']);
  _alias(result, 'citations_used', const <String>[
    'citationsUsed',
    'citations',
  ]);
  _alias(result, 'model_supplements', const <String>[
    'modelSupplements',
    'supplements',
  ]);

  result['translation'] = _mapList(result['translation'], (item) {
    final map = <String, Object?>{...item};
    _alias(map, 'quote_id', const <String>['quoteId', 'quote']);
    _alias(map, 'text', const <String>['translation', 'value']);
    _alias(map, 'label', const <String>['type']);
    _alias(map, 'citation_ids', const <String>['citationIds', 'citations']);
    map['label'] = '模型译文';
    return map;
  });
  result['segments'] = _mapList(result['segments'], (item) {
    final map = <String, Object?>{...item};
    _alias(map, 'id', const <String>['segment_id', 'segmentId']);
    _alias(map, 'quote_id', const <String>['quoteId', 'quote']);
    _alias(map, 'literal', const <String>['original', 'source_text']);
    _alias(map, 'interpretation', const <String>[
      'meaning',
      'explanation',
      'text',
    ]);
    _alias(map, 'word_notes', const <String>['wordNotes', 'words']);
    _alias(map, 'grammar_notes', const <String>['grammarNotes', 'grammar']);
    _alias(map, 'epistemic', const <String>['type', 'claim_type']);
    map['word_notes'] = _mapList(map['word_notes'], (note) {
      final value = <String, Object?>{...note};
      _alias(value, 'token_id', const <String>['tokenId', 'token']);
      _alias(value, 'citation_ids', const <String>[
        'citationIds',
        'citations',
      ]);
      _alias(value, 'reading', const <String>['pronunciation']);
      _alias(value, 'sense', const <String>['meaning']);
      return value;
    });
    map['grammar_notes'] = _mapList(map['grammar_notes'], (note) {
      final value = <String, Object?>{...note};
      _alias(value, 'pattern_id', const <String>['patternId', 'pattern']);
      _alias(value, 'citation_ids', const <String>[
        'citationIds',
        'citations',
      ]);
      _alias(value, 'explanation', const <String>['meaning', 'text']);
      return value;
    });
    return map;
  });
  result['interpretations'] = _mapList(result['interpretations'], (item) {
    final map = <String, Object?>{...item};
    _alias(map, 'id', const <String>['interpretation_id']);
    _alias(map, 'meaning', const <String>['text', 'explanation']);
    _alias(map, 'citation_ids', const <String>['citationIds', 'citations']);
    return map;
  });
  result['unresolved'] = _mapList(result['unresolved'], (item) {
    final map = <String, Object?>{...item};
    _alias(map, 'quote_id', const <String>['quoteId', 'quote']);
    _alias(map, 'reason', const <String>['message', 'explanation']);
    return map;
  });
  result['model_supplements'] = _mapList(result['model_supplements'], (item) {
    final map = <String, Object?>{...item};
    _alias(map, 'text', const <String>['content', 'message']);
    map['label'] = '模型补充';
    return map;
  });
  return result;
}

void _alias(
  Map<String, Object?> map,
  String canonical,
  List<String> aliases,
) {
  if (map.containsKey(canonical)) return;
  for (final alias in aliases) {
    if (map.containsKey(alias)) {
      map[canonical] = map[alias];
      return;
    }
  }
}

List<Object?> _mapList(
  Object? value,
  Map<String, Object?> Function(Map<String, Object?> item) convert,
) {
  if (value is! List) return const <Object?>[];
  return <Object?>[
    for (final item in value)
      if (item is Map)
        convert(item.map((key, value) => MapEntry(key.toString(), value)))
      else
        item,
  ];
}
