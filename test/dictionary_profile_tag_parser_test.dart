import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_profile_tag_parser.dart';

void main() {
  test('parses flat profile tags for multiple dictionaries', () {
    const raw = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[LANGUAGES]ja|zh[/LANGUAGES]
[HEADWORD_FIELDS]見出し|かな[/HEADWORD_FIELDS]
[DEFINITION_FIELDS]語義|例文[/DEFINITION_FIELDS]
[FLAGS]ruby|examples[/FLAGS]
[EXACT_FORMS]漢字|かな[/EXACT_FORMS]
[PREFIX]yes[/PREFIX]
[SEARCH_NOTES]支持前缀[/SEARCH_NOTES]
[STRENGTHS]多义项[/STRENGTHS]
[CAVEATS]含图片[/CAVEATS]
[RECOMMENDED]lemma[/RECOMMENDED]
[ENTRY_NOTES]条目说明[/ENTRY_NOTES]
[/PROFILE]
[PROFILE]
[ID]dict_b[/ID]
[TITLE]B[/TITLE]
[KIND]類語辞典[/KIND]
[FLAGS]audio[/FLAGS]
[PREFIX]no[/PREFIX]
[/PROFILE]
''';

    final profiles = parseTaggedProfiles(
      raw,
      language: AgentProfileLanguage.chinese,
    );
    expect(profiles, hasLength(2));
    final first = profiles.first;
    expect(first.dictionaryId, 'dict_a');
    expect(first.title, 'A');
    expect(first.kind, '国語辞典');
    expect(first.languages, <String>['ja', 'zh']);
    expect(first.entryStructure.hasRuby, isTrue);
    expect(first.entryStructure.hasExamples, isTrue);
    expect(first.entryStructure.hasAudio, isFalse);
    expect(first.entryStructure.notes, '条目说明');
    expect(first.searchBehavior.prefixSuggestions, isTrue);
    expect(first.searchBehavior.notes, '支持前缀');
    expect(first.language, 'zh');
    expect(first.confidence, greaterThan(0));

    final second = profiles.last;
    expect(second.entryStructure.hasAudio, isTrue);
    expect(second.searchBehavior.prefixSuggestions, isFalse);
    expect(second.strengths, isEmpty);
  });

  test('ignores malformed blocks without an id', () {
    final profiles = parseTaggedProfiles(
      '[PROFILE][TITLE]No id[/TITLE][/PROFILE]',
      language: AgentProfileLanguage.chinese,
    );
    expect(profiles, isEmpty);
  });
}
