import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
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
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/ocr_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_mobile/state/agent_ocr_variants.dart';
import 'package:rikai_mobile/state/agent_run_services.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

const _baseline = AgentOcrVariant(
  id: 'var-1',
  engine: 'paddle_v5',
  mode: OcrMode.auto,
  text: '何卒コンニチハ',
  confidence: 0.9,
);

class _FakeOcr implements OcrPort {
  _FakeOcr({this.throwOnAuto = false});

  final bool throwOnAuto;
  final List<OcrMode> calls = <OcrMode>[];
  bool cancelled = false;

  @override
  bool get horizontalAvailable => true;

  @override
  bool get verticalAvailable => true;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> ensureReady() async {}

  @override
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
  }) async {
    calls.add(mode);
    if (throwOnAuto && mode == OcrMode.auto) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.modelMissing,
        'OCR 模型未安装',
      );
    }
    return switch (mode) {
      OcrMode.auto => const OcrRun(
        engine: 'paddle_v5',
        mode: OcrMode.auto,
        text: '何卒コンニチハ',
        elapsedMs: 10,
        confidence: 0.9,
      ),
      OcrMode.horizontal => const OcrRun(
        engine: 'paddle_v5',
        mode: OcrMode.horizontal,
        text: '何卒コンバンハ',
        elapsedMs: 11,
        confidence: 0.8,
      ),
      OcrMode.vertical => const OcrRun(
        engine: 'paddle_v5',
        mode: OcrMode.vertical,
        text: '何卒コンバンハ',
        elapsedMs: 12,
        confidence: 0.7,
      ),
    };
  }
}

class _BlockingOcr implements OcrPort {
  final List<OcrMode> calls = <OcrMode>[];
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool cancelled = false;

  @override
  bool get horizontalAvailable => true;

  @override
  bool get verticalAvailable => false;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<void> ensureReady() async {}

  @override
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
  }) async {
    calls.add(mode);
    if (!started.isCompleted) started.complete();
    await release.future;
    return const OcrRun(
      engine: 'paddle_v5',
      mode: OcrMode.horizontal,
      text: '何卒コンバンハ',
      elapsedMs: 1,
      confidence: 0.8,
    );
  }
}

class _FakeTokenize implements TokenizePort {
  @override
  Future<List<Token>> analyze(String text) async {
    final surfaces = <String>['何卒', 'コンニチハ', 'テスト'];
    return <Token>[
      for (var index = 0; index < surfaces.length; index++)
        Token.fromFeatures(
          surface: surfaces[index],
          features: _features(surfaces[index]),
          start: index,
          end: index + 1,
        ),
    ];
  }

  static List<String> _features(String surface) {
    final features = List<String>.filled(Token.expectedFeatureCount, '*');
    features[0] = '名詞';
    features[7] = surface;
    features[8] = surface;
    features[20] = surface;
    return features;
  }
}

class _FakeLookup implements LookupPort {
  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    final hit = request.query == '何卒';
    return LookupResult(
      query: request.query,
      candidates: request.rawCandidates,
      groups: <DictionaryLookupGroup>[
        DictionaryLookupGroup(
          dictionary: request.dictionaries.first,
          entries: hit
              ? <LookupEntry>[
                  LookupEntry(
                    matchedKey: request.query,
                    headword: request.query,
                    html: '<b>${request.query}</b>',
                  ),
                ]
              : const <LookupEntry>[],
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
    return prefix == 'ニ' ? const <String>['ニッポン'] : const <String>[];
  }
}

AgentRunServices _services(OcrPort ocr) {
  return AgentRunServices(
    ocrPort: ocr,
    tokenizePort: _FakeTokenize(),
    lookupPort: _FakeLookup(),
    samplePort: _UnusedSamplePort(),
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    profileRepository: InMemoryDictionaryProfileRepository(),
    unidicRepository: InMemoryUnidicProfileRepository(),
    llmFactory: (_) => FakeProvider(responseText: ''),
    cancelOcr: ocr.cancel,
  );
}

class _UnusedSamplePort implements DictionarySamplePort {
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

void main() {
  test(
    'generates alternatives, dedupes identical text and suggests repairs',
    () async {
      final ocr = _FakeOcr();
      final container = ProviderContainer(
        overrides: [
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(ocr),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentOcrVariantsProvider.notifier);

      await controller.generate(
        images: const <AgentImageInput>[
          AgentImageInput(id: 'img-1', localPath: '/tmp/one.png'),
        ],
        baselineVariants: const <String, List<AgentOcrVariant>>{
          'img-1': <AgentOcrVariant>[
            AgentOcrVariant(
              id: 'var-1',
              engine: 'paddle_v5',
              mode: OcrMode.auto,
              text: '何卒コンニチハ',
              confidence: 0.9,
            ),
          ],
        },
        dictionaries: const <DictionaryInfo>[_dictionary],
      );

      final state = container.read(agentOcrVariantsProvider);
      expect(state.loading, isFalse);
      expect(state.errorCode, isNull);
      expect(ocr.calls, <OcrMode>[OcrMode.horizontal, OcrMode.vertical]);
      expect(state.extraVariants['img-1'], hasLength(1));
      expect(state.extraVariants['img-1']!.single.mode, OcrMode.horizontal);
      expect(state.qualities['img-1'], containsPair('var-1', isNotNull));
      expect(
        state.qualities['img-1'],
        containsPair('var-img-1-horizontal-paddle_v5', isNotNull),
      );
      expect(state.generatedImages, contains('img-1'));
      expect(state.repairs['img-1'], isNotEmpty);
      expect(state.repairBaselineIds['img-1'], 'var-1');
      expect(state.repairs['img-1']!.single.original, 'ニチ');
      expect(state.repairs['img-1']!.single.candidates.single.text, 'ニッポン');
    },
  );

  test(
    're-generating after a variant switch excludes the new baseline',
    () async {
      final ocr = _FakeOcr();
      final container = ProviderContainer(
        overrides: [
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(ocr),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentOcrVariantsProvider.notifier);
      const image = AgentImageInput(
        id: 'img-1',
        localPath: '/tmp/one.png',
        selectedVariantId: 'var-1',
      );

      await controller.generate(
        images: const <AgentImageInput>[image],
        baselineVariants: const <String, List<AgentOcrVariant>>{
          'img-1': <AgentOcrVariant>[_baseline],
        },
        dictionaries: const <DictionaryInfo>[_dictionary],
      );
      final first = container.read(agentOcrVariantsProvider);
      final switched = first.extraVariants['img-1']!.single;

      await controller.generate(
        images: <AgentImageInput>[
          AgentImageInput(
            id: 'img-1',
            localPath: '/tmp/one.png',
            selectedVariantId: switched.id,
          ),
        ],
        baselineVariants: <String, List<AgentOcrVariant>>{
          'img-1': <AgentOcrVariant>[_baseline, switched],
        },
        dictionaries: const <DictionaryInfo>[_dictionary],
      );

      final state = container.read(agentOcrVariantsProvider);
      expect(state.repairBaselineIds['img-1'], switched.id);
      expect(
        state.extraVariants['img-1']!.map((variant) => variant.id),
        contains('var-1'),
      );
      expect(
        state.extraVariants['img-1']!.map((variant) => variant.id),
        isNot(contains(switched.id)),
      );
    },
  );

  test(
    'cancel stops an in-flight comparison and keeps no partial state',
    () async {
      final ocr = _BlockingOcr();
      final container = ProviderContainer(
        overrides: [
          agentRunServicesProvider.overrideWithValue(
            ({required bool needsOcr, bool Function()? isCancelled}) async =>
                _services(ocr),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(agentOcrVariantsProvider.notifier);

      final future = controller.generate(
        images: const <AgentImageInput>[
          AgentImageInput(id: 'img-1', localPath: '/tmp/one.png'),
        ],
        baselineVariants: const <String, List<AgentOcrVariant>>{
          'img-1': <AgentOcrVariant>[_baseline],
        },
        dictionaries: const <DictionaryInfo>[_dictionary],
      );
      await ocr.started.future;
      controller.cancel();
      await future;

      final state = container.read(agentOcrVariantsProvider);
      expect(ocr.cancelled, isTrue);
      expect(state.loading, isFalse);
      expect(state.extraVariants, isEmpty);
    },
  );

  test('baseline OCR failure is reported with a stable code', () async {
    final ocr = _FakeOcr(throwOnAuto: true);
    final container = ProviderContainer(
      overrides: [
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(ocr),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentOcrVariantsProvider.notifier);

    await controller.generate(
      images: const <AgentImageInput>[
        AgentImageInput(id: 'img-1', localPath: '/tmp/one.png'),
      ],
      baselineVariants: const <String, List<AgentOcrVariant>>{},
      dictionaries: const <DictionaryInfo>[_dictionary],
    );

    final state = container.read(agentOcrVariantsProvider);
    expect(state.loading, isFalse);
    expect(state.errorCode, AgentToolErrorCode.modelMissing);
    expect(state.extraVariants, isEmpty);
  });

  test('clear resets variants and stops an in-flight generation', () async {
    final ocr = _FakeOcr();
    final container = ProviderContainer(
      overrides: [
        agentRunServicesProvider.overrideWithValue(
          ({required bool needsOcr, bool Function()? isCancelled}) async =>
              _services(ocr),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(agentOcrVariantsProvider.notifier);

    await controller.generate(
      images: const <AgentImageInput>[
        AgentImageInput(id: 'img-1', localPath: '/tmp/one.png'),
      ],
      baselineVariants: const <String, List<AgentOcrVariant>>{
        'img-1': <AgentOcrVariant>[
          AgentOcrVariant(
            id: 'var-1',
            engine: 'paddle_v5',
            mode: OcrMode.auto,
            text: '何卒コンニチハ',
            confidence: 0.9,
          ),
        ],
      },
      dictionaries: const <DictionaryInfo>[_dictionary],
    );
    controller.clear();
    final state = container.read(agentOcrVariantsProvider);
    expect(state.extraVariants, isEmpty);
    expect(state.loading, isFalse);
  });
}
