import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_tool.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/dictionary_sample.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/agent_capability_exception.dart';
import 'package:rikai_mobile/services/agent/ports/dictionary_sample_port.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/ocr_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/state/agent_run_controller.dart';
import 'package:rikai_mobile/state/agent_run_services.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

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

const _analysisJson = <String, Object?>{
  'source_id': 'src-1',
  'translation': <Object?>[
    <String, Object?>{'quote_id': 'q1', 'text': '请多关照。', 'label': '模型译文'},
  ],
  'segments': <Object?>[
    <String, Object?>{
      'id': 'seg-1',
      'quote_id': 'q1',
      'literal': '何卒',
      'interpretation': '正式请求',
      'epistemic': 'dictionary_fact',
      'word_notes': <Object?>[
        <String, Object?>{
          'token_id': 't1',
          'surface': '何卒',
          'sense': '请务必',
          'citation_ids': <String>['source-1'],
        },
      ],
    },
  ],
};

const _profileJson = <String, Object?>{
  'profiles': <Object?>[
    <String, Object?>{
      'dictionary_id': 'dict_a',
      'title': 'A',
      'kind': '国語辞典',
      'entry_structure': <String, Object?>{},
      'search_behavior': <String, Object?>{},
      'confidence': 0.8,
      'schema_version': 1,
      'language': 'zh',
    },
  ],
};

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
      yield LlmEvent(
        type: LlmEventType.textDelta,
        text: jsonEncode(_profileJson),
      );
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
    yield LlmEvent(
      type: LlmEventType.textDelta,
      text: jsonEncode(_analysisJson),
    );
    yield LlmEvent.done();
  }
}

AgentRunServices _services(LlmPort llm) {
  return AgentRunServices(
    ocrPort: _FakeOcr(),
    tokenizePort: _FakeTokenize(),
    lookupPort: _FakeLookup(),
    samplePort: _FakeSample(),
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    profileRepository: InMemoryDictionaryProfileRepository(),
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

void main() {
  test('start reaches done with evidence and progress counts', () async {
    final provider = FakeProvider(
      responseSequence: <String>[
        jsonEncode(_profileJson),
        jsonEncode(_analysisJson),
      ],
    );
    final container = ProviderContainer(
      overrides: [
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

  test('immediate validation error keeps the sent text', () async {
    final container = ProviderContainer(
      overrides: [
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
