import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/dictionary_sample.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_profile_markdown.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/dictionary_sample_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';

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

class _FakeSamplePort implements DictionarySamplePort {
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
    llm: llm ?? FakeProvider(responseText: jsonEncode(_profileJson)),
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
    expect(await repository.load('dict_a'), isNull);
    expect(samples.calls, 1);
  });

  test('confirmed profile is reused without another LLM call', () async {
    final repository = InMemoryDictionaryProfileRepository();
    final samples = _FakeSamplePort();
    final llm = FakeProvider(responseText: jsonEncode(_profileJson));
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
    final llm = FakeProvider(responseText: jsonEncode(_profileJson));
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
    final bad = Map<String, Object?>.from(_profileJson)
      ..['dictionary_id'] = 'other';
    final service = _service(
      samples: samples,
      repository: repository,
      llm: FakeProvider(responseText: jsonEncode(bad)),
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
    final profileB = Map<String, Object?>.from(_profileJson)
      ..['dictionary_id'] = 'dict_b'
      ..['title'] = 'B';
    final llm = FakeProvider(
      responseText: jsonEncode(<String, Object?>{
        'profiles': <Object?>[_profileJson, profileB],
      }),
    );
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

  test('profile markdown follows the selected language', () {
    final profile = DictionaryProfile.fromJson(_profileJson);
    expect(
      profileToMarkdown(profile, AgentProfileLanguage.chinese),
      contains('类型'),
    );
    expect(
      profileToMarkdown(profile, AgentProfileLanguage.english),
      contains('Type'),
    );
    expect(
      profileToMarkdown(profile, AgentProfileLanguage.japanese),
      contains('種類'),
    );
  });
}
