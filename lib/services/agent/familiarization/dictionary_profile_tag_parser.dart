import '../../../core/models/agent/agent_profile.dart';
import '../tag_block_integrity.dart';

const _profileFieldTags = <String>{
  'ID',
  'TITLE',
  'KIND',
  'LANGUAGES',
  'HEADWORD_FIELDS',
  'DEFINITION_FIELDS',
  'FLAGS',
  'EXACT_FORMS',
  'PREFIX',
  'SEARCH_NOTES',
  'STRENGTHS',
  'CAVEATS',
  'RECOMMENDED',
  'ENTRY_NOTES',
};

/// Reports unbalanced or mis-nested profile blocks. Parsing may still succeed
/// on a truncated batch; callers use these errors to request repair.
List<String> dictionaryProfileTagIntegrityErrors(String raw) {
  return tagBlockIntegrityErrors(
    raw,
    blockTags: <String>{'PROFILE', ..._profileFieldTags},
    rootOnlyTags: const <String>{'PROFILE'},
    requiredParent: <String, String>{
      for (final tag in _profileFieldTags) tag: 'PROFILE',
    },
    singleInParent: _profileFieldTags,
  );
}

/// Parses the flat tag format used for dictionary profiles.
///
/// The model writes only descriptive text inside simple tags; the parser
/// supplies schema version, confidence and language. Missing fields fall back
/// conservatively instead of invalidating the whole batch.
List<DictionaryProfile> parseTaggedProfiles(
  String raw, {
  required AgentProfileLanguage language,
}) {
  final profiles = <DictionaryProfile>[];
  final profilePattern = RegExp(
    r'\[PROFILE\]([\s\S]*?)\[/PROFILE\]',
    caseSensitive: false,
  );
  for (final match in profilePattern.allMatches(raw)) {
    final block = match.group(1) ?? '';
    final id = _tag(block, 'ID');
    if (id.isEmpty) continue;
    final title = _tag(block, 'TITLE');
    final kind = _tag(block, 'KIND');
    final flags = <String>{
      for (final flag in _listTag(block, 'FLAGS')) flag.toLowerCase(),
    };
    final prefix = _tag(block, 'PREFIX').toLowerCase();
    profiles.add(
      DictionaryProfile(
        dictionaryId: id,
        title: title.isEmpty ? id : title,
        kind: kind.isEmpty ? 'unknown' : kind,
        languages: _listTag(block, 'LANGUAGES'),
        entryStructure: DictionaryEntryStructure(
          headwordFields: _listTag(block, 'HEADWORD_FIELDS'),
          definitionFields: _listTag(block, 'DEFINITION_FIELDS'),
          hasRuby: flags.contains('ruby'),
          hasKanjiInfo: flags.contains('kanji'),
          hasExamples: flags.contains('examples'),
          hasAudio: flags.contains('audio'),
          hasImages: flags.contains('images'),
          notes: _tag(block, 'ENTRY_NOTES'),
        ),
        searchBehavior: DictionarySearchBehavior(
          exactForms: _listTag(block, 'EXACT_FORMS'),
          prefixSuggestions: prefix == 'yes' || prefix == 'true',
          notes: _tag(block, 'SEARCH_NOTES'),
        ),
        strengths: _listTag(block, 'STRENGTHS'),
        caveats: _listTag(block, 'CAVEATS'),
        recommendedQueryForms: _listTag(block, 'RECOMMENDED'),
        confidence: 0.8,
        schemaVersion: 1,
        language: language.wireName,
      ),
    );
  }
  return profiles;
}

String _tag(String block, String name) {
  final match = RegExp(
    '\\[$name\\]([\\s\\S]*?)\\[/$name\\]',
    caseSensitive: false,
  ).firstMatch(block);
  return (match?.group(1) ?? '').trim();
}

List<String> _listTag(String block, String name) {
  final value = _tag(block, name);
  if (value.isEmpty) return const <String>[];
  return <String>[
    for (final item in value.split(RegExp(r'[|｜\n]')))
      if (item.trim().isNotEmpty) item.trim(),
  ];
}
