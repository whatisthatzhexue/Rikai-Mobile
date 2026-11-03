import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/dictionary_sample.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_fingerprint.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/dictionary_sample_port.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/ocr_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/state/agent_profile_inbox.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/agent_run_controller.dart';
import 'package:rikai_mobile/state/agent_run_services.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:rikai_ocr/rikai_ocr.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/missing/a.mdx',
  order: 0,
);

const _provider = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: 'Test',
  baseUrl: 'https://example.invalid',
  smallModel: 'small',
  complexModel: 'large',
  supportsStreaming: false,
);

const _analysisTagged = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

const _profileTagged = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[/PROFILE]
''';

class _FakeOcr implements OcrPort {
  @override
  bool get horizontalAvailable => true;

  @override
  bool get verticalAvailable => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> ensureReady() async {}

  @override
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
    String? engine,
  }) async {
    return const OcrRun(
      engine: 'paddle_v5',
      mode: OcrMode.auto,
      text: '何卒',
      elapsedMs: 1,
      confidence: 0.99,
    );
  }
}

class _FakeTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '副詞';
    features[7] = '何卒';
    features[8] = '何卒';
    features[20] = 'ナニトゾ';
    return <Token>[
      Token.fromFeatures(surface: '何卒', features: features, start: 0, end: 2),
    ];
  }
}

class _FakeLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: const <LookupEntry>[
            LookupEntry(matchedKey: '何卒', headword: '何卒', html: '<b>なにとぞ</b>'),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    return const <String>[];
  }
}

class _FakeSample implements DictionarySamplePort {
  @override
  Future<DictionarySample> sample(
    DictionaryInfo dictionary, {
    int maxEntries = 12,
  }) async {
    return DictionarySample(
      dictionaryId: dictionary.id,
      metadata: const DictionarySampleMetadata(title: 'A'),
      entries: const <DictionarySampleEntry>[],
    );
  }
}

class _BlockingSecondAnalysisProvider implements LlmPort {
  int calls = 0;
  final Completer<void> secondCall = Completer<void>();

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    if (calls == 2) await secondCall.future;
    yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
    yield LlmEvent.done();
  }
}

class _FailingSecondAnalysisProvider implements LlmPort {
  int calls = 0;

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    if (calls == 2) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.providerUnavailable,
        '模型服务暂时不可用',
      );
    }
    yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
    yield LlmEvent.done();
  }
}

class _CancelAwareProvider implements LlmPort {
  int calls = 0;
  final Completer<void> _cancelled = Completer<void>();

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    if (calls == 1) {
      yield LlmEvent(type: LlmEventType.textDelta, text: _profileTagged);
      yield LlmEvent.done();
      return;
    }
    cancellation?.addListener(() {
      if (!_cancelled.isCompleted) _cancelled.complete();
    });
    await _cancelled.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    if (cancellation?.isCancelled == true) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.toolCancelled,
        '已取消',
      );
    }
    yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
    yield LlmEvent.done();
  }
}

class _AutoSkipInbox extends AgentProfileInboxController {
  @override
  Future<List<ProfileConfirmation>> waitForAll(
    String runId,
    List<AgentProfileProposal> proposals,
  ) async {
    return <ProfileConfirmation>[
      for (final proposal in proposals)
        ProfileConfirmation(
          action: ProfileConfirmationAction.skipOnce,
          markdown: proposal.markdown,
        ),
    ];
  }
}

AgentRunServices _services(
  LlmPort llm, {
  DictionaryProfileRepository? profileRepository,
}) {
  return AgentRunServices(
    ocrPort: _FakeOcr(),
    tokenizePort: _FakeTokenize(),
    lookupPort: _FakeLookup(),
    samplePort: _FakeSample(),
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    profileRepository:
        profileRepository ?? InMemoryDictionaryProfileRepository(),
    unidicRepository: InMemoryUnidicProfileRepository(),
    llmFactory: (_) => llm,
    cancelOcr: () async {},
  );
}

Future<AgentRunSnapshot> _runToCompletion(
  ProviderContainer container,
  AgentRunController controller, {
  String text = '何卒',
  AgentProviderConfig provider = _provider,
}) async {
  await controller.start(
    userText: text,
    images: const <AgentImageInput>[],
    dictionaries: const <DictionaryInfo>[_dictionary],
    provider: provider,
    mode: AgentMode.strict,
    unidicPath: '',
    responseLanguage: AgentResponseLanguage.chinese,
    profileLanguage: AgentProfileLanguage.chinese,
  );
  return container.read(agentRunControllerProvider);
}

late SharedPreferences _preferences;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
  });

  test('start reaches done with evidence and progress counts', () async {
    final provider = FakeProvider(
      responseSequence: <String>[_profileTagged, _analysisTagged],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
        ),
        agentProfileInboxProvider.overrideWith(_AutoSkipInbox.new),
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(provider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentRunControllerProvider.notifier);

    final snapshot = await _runToCompletion(container, controller);

    expect(snapshot.status, AgentRunStatus.done);
    expect(snapshot.progressStep, 4);
    expect(snapshot.evidenceCount, 1);
    expect(snapshot.citationCount, 1);
    expect(snapshot.result, isNotNull);
    expect(provider.requests, hasLength(2));
  });

  test('cancel stops the run and keeps the cancelled status', () async {
    final provider = _CancelAwareProvider();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
        ),
        agentProfileInboxProvider.overrideWith(_AutoSkipInbox.new),
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(provider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentRunControllerProvider.notifier);

    final future = controller.start(
      userText: '何卒',
      images: const <AgentImageInput>[],
      dictionaries: const <DictionaryInfo>[_dictionary],
      provider: _provider,
      mode: AgentMode.strict,
      unidicPath: '',
      responseLanguage: AgentResponseLanguage.chinese,
      profileLanguage: AgentProfileLanguage.chinese,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.cancel();
    await future;

    final snapshot = container.read(agentRunControllerProvider);
    expect(snapshot.status, AgentRunStatus.cancelled);
    expect(snapshot.sentText, '何卒');
  });

  test('auto-accept saves profiles and continues without a sheet', () async {
    await _preferences.setBool('agent_profiles_auto_accept', true);
    final provider = FakeProvider(
      responseSequence: <String>[_profileTagged, _analysisTagged],
    );
    final repository = InMemoryDictionaryProfileRepository();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
        ),
        agentProfileRepositoryProvider.overrideWithValue(repository),
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(provider, profileRepository: repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentRunControllerProvider.notifier);

    final snapshot = await _runToCompletion(container, controller);
    expect(snapshot.status, AgentRunStatus.done);
    expect(provider.requests, hasLength(2));
    expect(container.read(agentProfileInboxProvider).pending, isEmpty);
    expect(
      (await repository.load('dict_a'))?.status,
      DictionaryProfileStatus.confirmed,
    );
  });

  test(
    'a generated profile gates tokenizing until the app inbox resolves it',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_profileTagged, _analysisTagged],
      );
      final repository = InMemoryDictionaryProfileRepository();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentLimitsProvider.overrideWithValue(
            const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
          ),
          agentProfileRepositoryProvider.overrideWithValue(repository),
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(provider, profileRepository: repository),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentRunControllerProvider.notifier);

      final future = controller.start(
        userText: '何卒',
        images: const <AgentImageInput>[],
        dictionaries: const <DictionaryInfo>[_dictionary],
        provider: _provider,
        mode: AgentMode.strict,
        unidicPath: '',
        responseLanguage: AgentResponseLanguage.chinese,
        profileLanguage: AgentProfileLanguage.chinese,
      );

      final inbox = container.read(agentProfileInboxProvider.notifier);
      for (
        var attempt = 0;
        attempt < 100 &&
            container.read(agentProfileInboxProvider).pending.isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final pending = container.read(agentProfileInboxProvider).pending;
      expect(pending, hasLength(1));
      expect(
        container.read(agentRunControllerProvider).status,
        AgentRunStatus.awaitingProfile,
      );
      // Only the profile-generation request ran; tokenizing/analysis is gated.
      expect(provider.requests, hasLength(1));
      expect(await repository.load('dict_a'), isNull);

      await inbox.resolve(
        pending.single.id,
        const ProfileConfirmation(
          action: ProfileConfirmationAction.save,
          markdown: 'trusted profile',
        ),
      );
      await future;
      final snapshot = container.read(agentRunControllerProvider);

      expect(snapshot.status, AgentRunStatus.done);
      expect(provider.requests, hasLength(2));
      expect((await repository.load('dict_a'))?.markdown, 'trusted profile');
      expect(container.read(agentProfileInboxProvider).pending, isEmpty);
    },
  );

  test(
    'regenerate keeps the previous result visible until the new one wins',
    () async {
      final provider = _BlockingSecondAnalysisProvider();
      final repository = InMemoryDictionaryProfileRepository();
      final fingerprint = await dictionaryProfileFingerprint(
        _dictionary,
        promptVersion: dictionaryProfilePromptVersion,
        schemaVersion: dictionaryProfileSchemaVersion,
        language: AgentProfileLanguage.chinese,
      );
      await repository.save(
        StoredDictionaryProfile(
          dictionaryId: 'dict_a',
          title: 'A',
          fingerprint: fingerprint,
          markdown: 'trusted profile',
          status: DictionaryProfileStatus.confirmed,
          modelId: 'small',
          promptVersion: dictionaryProfilePromptVersion,
          schemaVersion: dictionaryProfileSchemaVersion,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentLimitsProvider.overrideWithValue(
            const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
          ),
          agentProfileInboxProvider.overrideWith(_AutoSkipInbox.new),
          agentProfileRepositoryProvider.overrideWithValue(repository),
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(provider, profileRepository: repository),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentRunControllerProvider.notifier);

      final first = await _runToCompletion(container, controller);
      expect(first.status, AgentRunStatus.done);
      expect(first.result, isNotNull);

      final regeneration = controller.regenerate();
      final during = container.read(agentRunControllerProvider);
      expect(during.result, isNull);
      expect(during.retainedResult, same(first.result));
      expect(during.isRunning, isTrue);

      provider.secondCall.complete();
      await regeneration;
      final after = container.read(agentRunControllerProvider);
      expect(after.status, AgentRunStatus.done);
      expect(after.result, isNotNull);
      expect(after.retainedResult, isNull);
      expect(provider.calls, 2);
    },
  );

  test(
    'a failed regeneration restores the previous result with a notice',
    () async {
      final provider = _FailingSecondAnalysisProvider();
      final repository = InMemoryDictionaryProfileRepository();
      final fingerprint = await dictionaryProfileFingerprint(
        _dictionary,
        promptVersion: dictionaryProfilePromptVersion,
        schemaVersion: dictionaryProfileSchemaVersion,
        language: AgentProfileLanguage.chinese,
      );
      await repository.save(
        StoredDictionaryProfile(
          dictionaryId: 'dict_a',
          title: 'A',
          fingerprint: fingerprint,
          markdown: 'trusted profile',
          status: DictionaryProfileStatus.confirmed,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentLimitsProvider.overrideWithValue(
            const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
          ),
          agentProfileInboxProvider.overrideWith(_AutoSkipInbox.new),
          agentProfileRepositoryProvider.overrideWithValue(repository),
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(provider, profileRepository: repository),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentRunControllerProvider.notifier);

      final first = await _runToCompletion(container, controller);
      expect(first.result, isNotNull);

      await controller.regenerate();
      final after = container.read(agentRunControllerProvider);
      expect(after.status, AgentRunStatus.error);
      expect(after.result, same(first.result));
      expect(after.retainedResult, isNull);
      expect(after.resultRetainedAfterFailure, isTrue);
      expect(provider.calls, 2);
    },
  );

  test('immediate validation error keeps the sent text', () async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
            ),
        ),
        agentProfileInboxProvider.overrideWith(_AutoSkipInbox.new),
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(FakeProvider()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentRunControllerProvider.notifier);

    final snapshot = await _runToCompletion(
      container,
      controller,
      provider: _provider.copyWith(smallModel: '', complexModel: ''),
    );

    expect(snapshot.status, AgentRunStatus.error);
    expect(snapshot.sentText, '何卒');
    expect(snapshot.finishedAt, isNotNull);
  });
}
