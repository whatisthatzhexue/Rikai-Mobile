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
import 'package:rikai_mobile/services/agent/agent_background_service.dart';
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

const _analysisPart1 = '[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]\n';
const _analysisPart2 = '''
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

const _analysisCompletePrefix = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

class _AlwaysInterruptedProvider implements LlmPort {
  int calls = 0;

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
    if (calls == 2) {
      yield LlmEvent(
        type: LlmEventType.textDelta,
        text: _analysisCompletePrefix,
      );
    }
    throw const AgentCapabilityException(
      AgentToolErrorCode.providerUnavailable,
      'still offline',
    );
  }
}

class _ReconnectProvider implements LlmPort {
  int calls = 0;
  final List<LlmRequest> requests = <LlmRequest>[];

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    requests.add(request);
    if (calls == 1) {
      yield LlmEvent(type: LlmEventType.textDelta, text: _profileTagged);
      yield LlmEvent.done();
      return;
    }
    if (calls == 2) {
      yield LlmEvent(type: LlmEventType.textDelta, text: _analysisPart1);
      throw const AgentCapabilityException(
        AgentToolErrorCode.providerUnavailable,
        'connection lost',
      );
    }
    final continuation = request.messages[request.messages.length - 1];
    final partial = request.messages[request.messages.length - 2];
    expect(continuation.role, LlmRole.user);
    expect(continuation.text, contains('interrupted'));
    expect(partial.role, LlmRole.assistant);
    expect(partial.text, _analysisPart1);
    yield LlmEvent(type: LlmEventType.textDelta, text: _analysisPart2);
    yield LlmEvent.done();
  }
}

class _FakeBackground implements AgentBackgroundPort {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

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

class _HangingAfterFirstProvider implements LlmPort {
  int calls = 0;

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    if (calls == 1) {
      yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
      yield LlmEvent.done();
      return;
    }
    final released = Completer<void>();
    void release() {
      if (!released.isCompleted) released.complete();
    }

    cancellation?.addListener(release);
    try {
      await released.future;
    } finally {
      cancellation?.removeListener(release);
    }
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

class _BlockingRichTextProvider implements LlmPort {
  int calls = 0;
  final Completer<void> formattingStarted = Completer<void>();
  final Completer<void> releaseFormatting = Completer<void>();

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
    if (calls == 2) {
      yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
      yield LlmEvent.done();
      return;
    }
    if (!formattingStarted.isCompleted) formattingStarted.complete();
    await releaseFormatting.future;
    final text = request.messages.last.text;
    // Preserve the batch section markers and bold each section body.
    final response = text.replaceAllMapped(
      RegExp(r'(<<<RIKAI_SECTION ([^>]+)>>>)\n([\s\S]*?)\n<<<RIKAI_END \2>>>'),
      (match) =>
          '${match.group(1)}\n[BOLD]${match.group(3)}[/BOLD]\n'
          '<<<RIKAI_END ${match.group(2)}>>>',
    );
    yield LlmEvent(type: LlmEventType.textDelta, text: response);
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
      responseSequence: <String>[_analysisTagged, _profileTagged],
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
    // Deferred profile generation runs after the answer; wait for it before
    // asserting the provider request count.
    for (
      var attempt = 0;
      attempt < 100 && provider.requests.length < 2;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(provider.requests, hasLength(2));
  });

  test('stream interruption resumes from the complete prefix', () async {
    final provider = _ReconnectProvider();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: false,
            streamReconnectAttempts: 2,
            streamReconnectDelayMs: 1,
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
    expect(snapshot.result, isNotNull);
    expect(provider.calls, 3);
  });

  test('exhausted reconnect keeps a usable partial analysis', () async {
    final provider = _AlwaysInterruptedProvider();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentLimitsProvider.overrideWithValue(
          const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: false,
            streamReconnectAttempts: 1,
            streamReconnectDelayMs: 1,
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

    expect(provider.calls, 3);
    expect(snapshot.status, AgentRunStatus.done);
    expect(snapshot.result?.analysis.segments, isNotEmpty);
  });

  test('active run holds and releases the background service', () async {
    final provider = FakeProvider(
      responseSequence: <String>[_analysisTagged, _profileTagged],
    );
    final background = _FakeBackground();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_preferences),
        agentBackgroundServiceProvider.overrideWithValue(background),
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

    await _runToCompletion(container, controller);
    expect(background.starts, 1);
    expect(background.stops, 1);
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
    // Profiles are generated after the analysis now, so the analysis response
    // comes first and the profile response second.
    final provider = FakeProvider(
      responseSequence: <String>[_analysisTagged, _profileTagged],
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

    // Profile generation is deferred until after the answer; wait for the
    // background proposal and auto-accept write.
    for (
      var attempt = 0;
      attempt < 100 && (await repository.load('dict_a')) == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(provider.requests.length, greaterThanOrEqualTo(2));
    expect(container.read(agentProfileInboxProvider).pending, isEmpty);
    expect(
      (await repository.load('dict_a'))?.status,
      DictionaryProfileStatus.confirmed,
    );
  });

  test(
    'run deadline keeps the retained result and becomes retryable',
    () async {
      final provider = _HangingAfterFirstProvider();
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
          confirmedAt: DateTime.now(),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentLimitsProvider.overrideWithValue(
            const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: false,
              runDeadlineSeconds: 1,
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

      final first = await _runToCompletion(container, controller);
      expect(first.status, AgentRunStatus.done);
      final firstResult = first.result;
      expect(firstResult, isNotNull);

      final second = controller.start(
        userText: '何卒',
        images: const <AgentImageInput>[],
        dictionaries: const <DictionaryInfo>[_dictionary],
        provider: _provider,
        mode: AgentMode.strict,
        unidicPath: '',
        responseLanguage: AgentResponseLanguage.chinese,
        profileLanguage: AgentProfileLanguage.chinese,
        retainResult: firstResult,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final timedOut = container.read(agentRunControllerProvider);
      expect(timedOut.status, AgentRunStatus.error);
      expect(timedOut.errorCode, AgentToolErrorCode.toolTimeout);
      expect(timedOut.retryable, isTrue);
      expect(timedOut.result, same(firstResult));
      expect(timedOut.resultRetainedAfterFailure, isTrue);
      expect(timedOut.errorMessage, contains('超时'));
      await second;
    },
  );

  test(
    'missing profiles are generated after the answer without gating',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_analysisTagged, _profileTagged],
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
      final snapshot = container.read(agentRunControllerProvider);
      expect(snapshot.status, AgentRunStatus.done);
      expect(snapshot.result, isNotNull);
      // Analysis first, then the deferred profile generation.
      expect(provider.requests.length, greaterThanOrEqualTo(2));
      expect(await repository.load('dict_a'), isNull);

      await inbox.resolve(
        pending.single.id,
        const ProfileConfirmation(
          action: ProfileConfirmationAction.save,
          markdown: 'trusted profile',
        ),
      );
      await future;
      for (
        var attempt = 0;
        attempt < 100 && (await repository.load('dict_a')) == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        container.read(agentRunControllerProvider).status,
        AgentRunStatus.done,
      );
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
              // This test asserts the failure path; automatic reconnect would
              // legitimately turn the next attempt into a success.
              streamReconnectAttempts: 0,
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

  test(
    'rich text arrives after done without delaying the core result',
    () async {
      final provider = _BlockingRichTextProvider();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          agentLimitsProvider.overrideWithValue(
            const AgentLimits(
              maxCoverageFallback: 0,
              enableRichTextPostProcess: true,
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

      // `done` is delivered before the formatting requests complete.
      expect(snapshot.status, AgentRunStatus.done);
      expect(snapshot.result, isNotNull);
      expect(snapshot.richTextFormatting, isTrue);
      // Local conversion populates the display fields immediately; the
      // formatting model has not answered yet.
      expect(snapshot.result!.richOriginalText, '何卒');
      await provider.formattingStarted.future.timeout(
        const Duration(seconds: 5),
      );
      expect(
        container.read(agentRunControllerProvider).result!.richOriginalText,
        '何卒',
      );
      expect(
        container.read(agentRunControllerProvider).richTextFormatting,
        isTrue,
      );

      provider.releaseFormatting.complete();
      AgentRunSnapshot current = container.read(agentRunControllerProvider);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (current.result?.richOriginalText != '[BOLD]何卒[/BOLD]' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        current = container.read(agentRunControllerProvider);
      }

      expect(current.status, AgentRunStatus.done);
      expect(current.richTextFormatting, isFalse);
      expect(current.result?.richOriginalText, '[BOLD]何卒[/BOLD]');
      expect(current.result?.richSegmentTexts, <String>['[BOLD]正式请求[/BOLD]']);
      // Dictionary notes are local-only; the batch formatter does not touch
      // them.
      expect(current.result?.richSegmentNotes, <String>['何卒：请务必']);
    },
  );
}
