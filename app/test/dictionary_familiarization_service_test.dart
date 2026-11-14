import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_profile.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/models/dictionary_sample.dart';
import 'package:lexicandy/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:lexicandy/services/agent/familiarization/dictionary_profile_markdown.dart';
import 'package:lexicandy/services/agent/familiarization/profile_repository.dart';
import 'package:lexicandy/services/agent/ports/agent_capability_exception.dart';
import 'package:lexicandy/services/agent/ports/dictionary_sample_port.dart';
import 'package:lexicandy/services/agent/providers/fake_provider.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/tmp/rikai-not-present.mdx',
  entryCount: 10,
);

const _dictionaryB = DictionaryInfo(
  id: 'dict_b',
  title: 'B',
  mdxPath: '/tmp/rikai-not-present-b.mdx',
  entryCount: 20,
);

const _profileJson = <String, Object?>{
  'schema': 'rikai.dictionary.profile.v1',
  'dictionary_id': 'dict_a',
  'title': 'A',
  'kind': '国語辞典',
  'intro': '国語辞典のサンプル。',
  'language_pairs': <Map<String, Object?>>[
    <String, Object?>{'source': 'ja', 'target': 'ja', 'confidence': 0.85},
  ],
  'coverage': <String, Object?>{
    'sample_entries': 12,
    'entry_count': 1000,
    'headword_scripts': <String>['han', 'hiragana'],
    'definition_scripts': <String>['han', 'hiragana'],
    'feature_count': 2,
  },
  'entry_structure': <String, Object?>{
    'headword_fields': <String>['見出し'],
    'definition_fields': <String>['語義'],
    'has_examples': true,
  },
  'search_behavior': <String, Object?>{
    'exact_forms': <String>['漢字', 'かな'],
    'prefix_suggestions': true,
  },
  'strengths': <String>['多义项'],
  'caveats': <String>['含图片'],
  'recommended_query_forms': <String>['lemma'],
  'confidence': 0.8,
  'schema_version': 1,
};

const _profileTagged = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[INTRO]国語辞典のサンプル。[/INTRO]
[LANGUAGES]ja|ja[/LANGUAGES]
[HEADWORD_FIELDS]見出し[/HEADWORD_FIELDS]
[DEFINITION_FIELDS]語義[/DEFINITION_FIELDS]
[FLAGS]examples[/FLAGS]
[EXACT_FORMS]漢字|かな[/EXACT_FORMS]
[PREFIX]yes[/PREFIX]
[STRENGTHS]多义项[/STRENGTHS]
[CAVEATS]含图片[/CAVEATS]
[RECOMMENDED]lemma[/RECOMMENDED]
[/PROFILE]
''';

const _profileTaggedB = '''
[PROFILE]
[ID]dict_b[/ID]
[TITLE]B[/TITLE]
[KIND]類語辞典[/KIND]
[/PROFILE]
''';

const _profileTaggedOther = '''
[PROFILE]
[ID]other[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[/PROFILE]
''';

class _FakeSamplePort implements DictionarySamplePort {
  _FakeSamplePort({this.truncated = false});

  final bool truncated;
  int calls = 0;

  @override
  Future<DictionarySample> sample(
    DictionaryInfo dictionary, {
    int maxEntries = 12,
  }) async {
    calls++;
    return DictionarySample(
      dictionaryId: dictionary.id,
      metadata: DictionarySampleMetadata(
        title: dictionary.title,
        entryCount: 10,
      ),
      entries: const <DictionarySampleEntry>[
        DictionarySampleEntry(
          matchedKey: '何卒',
          headword: '何卒',
          snippet: 'なにとぞ',
          features: DictionarySampleFeatures(),
        ),
      ],
      truncated: truncated,
      unsampledProbes: truncated ? const <String>['は', 'です'] : const <String>[],
    );
  }
}

DictionaryFamiliarizationService _service({
  required _FakeSamplePort samples,
  required DictionaryProfileRepository repository,
  FakeProvider? llm,
}) {
  return DictionaryFamiliarizationService(
    samplePort: samples,
    repository: repository,
    llm: llm ?? FakeProvider(responseText: _profileTagged),
    smallModel: 'small',
  );
}

void main() {
  test('pending profile is not saved until the user confirms', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final service = _service(samples: samples, repository: repository);

    final result = await service.ensure(_dictionary);
    expect(result.action, FamiliarizationAction.pending);
    expect(result.draft!.kind, '国語辞典');
    expect(result.draft!.intro, '国語辞典のサンプル。');
    expect(result.draft!.languagePairs.single.label, 'ja→ja');
    expect(result.draft!.coverage.sampleEntries, 1);
    expect(result.draft!.coverage.entryCount, 10);
    expect(result.draft!.coverage.headwordScripts, contains('han'));
    expect(result.draft!.coverage.definitionScripts, contains('hiragana'));
    expect(await repository.load('dict_a'), isNull);
    expect(samples.calls, 1);
  });

  test('surfaces truncated samples in warnings and markdown only', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort(truncated: true);
    final llm = FakeProvider(responseText: _profileTagged);
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    final generation = await service.generateMany(<DictionaryInfo>[
      _dictionary,
    ]);

    expect(generation.proposals, hasLength(1));
    expect(generation.warnings.single, contains('2 项检查未覆盖'));
    final proposal = generation.proposals.single;
    expect(proposal.profile.coverage.sampleTruncated, isTrue);
    expect(proposal.profile.coverage.unsampledProbeCount, 2);
    expect(proposal.markdown, contains('样本提示'));
    expect(proposal.markdown, contains('2 项检查未覆盖'));

    // Truncation diagnostics stay local; the model-facing sample JSON keeps
    // its previous shape.
    final prompt = llm.requests.single.messages.last.text;
    expect(prompt, isNot(contains('"truncated"')));
    expect(prompt, isNot(contains('unsampled_probes')));
  });

  test('profile prompt asks for a one-sentence intro', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(responseText: _profileTagged);
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    await service.ensure(_dictionary);

    final prompt = llm.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(prompt, contains('[INTRO]'));
    expect(prompt, contains('one short sentence'));
  });

  test('confirmed profile is reused without another LLM call', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(responseText: _profileTagged);
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );
    var confirmations = 0;

    final created = await service.ensure(
      _dictionary,
      confirm: (profile, markdown) async {
        confirmations++;
        return ProfileConfirmation(
          action: ProfileConfirmationAction.save,
          markdown: 'custom summary',
        );
      },
    );
    expect(created.action, FamiliarizationAction.created);
    expect(created.stored!.markdown, 'custom summary');
    expect(confirmations, 1);

    final reused = await service.ensure(_dictionary);
    expect(reused.action, FamiliarizationAction.reuse);
    expect(samples.calls, 1);
    expect(llm.requests, hasLength(1));
  });

  test('skip once does not persist and a later call can retry', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final service = _service(samples: samples, repository: repository);

    final skipped = await service.ensure(
      _dictionary,
      confirm: (profile, markdown) async => ProfileConfirmation(
        action: ProfileConfirmationAction.skipOnce,
        markdown: markdown,
      ),
    );
    expect(skipped.action, FamiliarizationAction.skipped);
    expect(await repository.load('dict_a'), isNull);

    final created = await service.ensure(
      _dictionary,
      confirm: (profile, markdown) async => ProfileConfirmation(
        action: ProfileConfirmationAction.save,
        markdown: markdown,
      ),
    );
    expect(created.action, FamiliarizationAction.created);
    expect(samples.calls, 2);
  });

  test('decline is remembered for the same fingerprint', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(responseText: _profileTagged);
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    final declined = await service.ensure(
      _dictionary,
      confirm: (profile, markdown) async => const ProfileConfirmation(
        action: ProfileConfirmationAction.decline,
        markdown: '',
      ),
    );
    expect(declined.action, FamiliarizationAction.declined);
    expect(
      (await repository.load('dict_a'))!.status,
      DictionaryProfileStatus.declined,
    );

    final remembered = await service.ensure(_dictionary);
    expect(remembered.action, FamiliarizationAction.declined);
    expect(samples.calls, 1);
    expect(llm.requests, hasLength(1));
  });

  test('a mismatched dictionary id is rejected', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final service = _service(
      samples: samples,
      repository: repository,
      llm: FakeProvider(responseText: _profileTaggedOther),
    );

    await expectLater(
      service.ensure(_dictionary),
      throwsA(isA<AgentCapabilityException>()),
    );
    expect(await repository.load('dict_a'), isNull);
  });

  test('generates multiple missing profiles in one provider request', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(responseText: '$_profileTagged\n$_profileTaggedB');
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    final batch = await service.ensureMany(
      <DictionaryInfo>[_dictionary, _dictionaryB],
      confirm: (profile, markdown) async => ProfileConfirmation(
        action: ProfileConfirmationAction.save,
        markdown: markdown,
      ),
    );

    expect(batch.results, hasLength(2));
    expect(batch.warnings, isEmpty);
    expect(llm.requests, hasLength(1));
    expect(await repository.load('dict_a'), isNotNull);
    expect(await repository.load('dict_b'), isNotNull);
  });

  test('tagged profile output is parsed into a pending proposal', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(
      responseText: '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[HEADWORD_FIELDS]見出し[/HEADWORD_FIELDS]
[DEFINITION_FIELDS]語義[/DEFINITION_FIELDS]
[FLAGS]ruby|examples[/FLAGS]
[PREFIX]yes[/PREFIX]
[STRENGTHS]多义项[/STRENGTHS]
[/PROFILE]
''',
    );
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    final result = await service.ensure(_dictionary);
    expect(result.action, FamiliarizationAction.pending);
    expect(result.draft!.kind, '国語辞典');
    expect(result.draft!.entryStructure.hasRuby, isTrue);
    expect(llm.requests, hasLength(1));
  });

  test('broken profile tags get one format-correction call', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(
      responseSequence: <String>[
        'Here is the profile without any tags.',
        '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[/PROFILE]
''',
      ],
    );
    final service = _service(
      samples: samples,
      repository: repository,
      llm: llm,
    );

    final result = await service.ensure(_dictionary);
    expect(result.action, FamiliarizationAction.pending);
    expect(llm.requests, hasLength(2));
    final repairText = llm.requests.last.messages
        .map((message) => message.text)
        .join('\n');
    expect(repairText, contains('FORMAT CORRECTION TASK'));
    expect(repairText, contains('Previous output'));
  });

  test(
    'orphan profile tag gets one format correction even when it parses',
    () async {
      final repository = InMemoryDictionaryProfileRepository();
      final samples = _FakeSamplePort();
      final llm = FakeProvider(
        responseSequence: <String>['$_profileTagged[/PROFILE]', _profileTagged],
      );
      final service = _service(
        samples: samples,
        repository: repository,
        llm: llm,
      );

      final result = await service.ensure(_dictionary);
      expect(result.action, FamiliarizationAction.pending);
      expect(llm.requests, hasLength(2));
      final repairText = llm.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairText, contains('多余的结束标签 [/PROFILE]'));
    },
  );

  test('profile markdown follows the selected language', () {
    final profile = DictionaryProfile.fromJson(_profileJson);
    final chinese = profileToMarkdown(profile, AgentProfileLanguage.chinese);
    expect(chinese, contains('类型'));
    expect(chinese, contains('国語辞典のサンプル。'));
    expect(chinese, contains('ja→ja'));
    expect(chinese, contains('覆盖样本'));
    expect(chinese, contains('样本条数: 12'));
    expect(
      profileToMarkdown(profile, AgentProfileLanguage.english),
      contains('Type'),
    );
    expect(
      profileToMarkdown(profile, AgentProfileLanguage.japanese),
      contains('種類'),
    );
  });

  test('persistAgentProfileDecision stores corrected language pairs', () async {
    final original = DictionaryProfile.fromJson(_profileJson);
    final corrected = original.copyWith(
      languagePairs: const <DictionaryLanguagePair>[
        DictionaryLanguagePair(source: 'ja', target: 'zh', confidence: 1),
      ],
    );
    final repository = InMemoryDictionaryProfileRepository();
    final markdown = updateLanguagePairsMarkdown(
      profileToMarkdown(original),
      corrected,
      AgentProfileLanguage.chinese,
    );
    await persistAgentProfileDecision(
      repository: repository,
      proposal: AgentProfileProposal(
        id: 'proposal-1',
        dictionary: _dictionary,
        fingerprint: 'fingerprint',
        profile: original,
        markdown: profileToMarkdown(original),
      ),
      action: ProfileConfirmationAction.save,
      markdown: markdown,
      profile: corrected,
    );

    final stored = await repository.load('dict_a');
    expect(stored?.profile?.languagePairs.single.label, 'ja→zh');
    expect(stored?.markdown, contains('- 语言: ja→zh'));
  });
}
