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
  final List<(OcrMode, String?)> calls = <(OcrMode, String?)>[];
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
    String? engine,
  }) async {
    calls.add((mode, engine));
    if (throwOnAuto && mode == OcrMode.auto && engine == null) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.modelMissing,
        'OCR 模型未安装',
      );
    }
    final effectiveEngine = engine ?? 'paddle_v5';
    return OcrRun(
      engine: effectiveEngine,
      mode: mode,
      text: mode == OcrMode.auto ? '何卒コンニチハ' : '何卒コンバンハ',
      elapsedMs: 10 + mode.index,
      confidence: switch (mode) {
        OcrMode.auto => 0.9,
        OcrMode.horizontal => 0.8,
        OcrMode.vertical => 0.7,
      },
    );
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
    String? engine,
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
    'generates distinct engine/orientation combinations and suggests repairs',
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
      expect(ocr.calls, <(OcrMode, String?)>[
        (OcrMode.horizontal, 'paddle_v5'),
        (OcrMode.vertical, 'manga_ocr'),
        (OcrMode.vertical, 'paddle_v5'),
      ]);
      expect(state.extraVariants['img-1'], hasLength(3));
      expect(
        state.extraVariants['img-1']!.map((variant) => variant.mode),
        containsAll(<OcrMode>[OcrMode.horizontal, OcrMode.vertical]),
      );
      expect(
        state.extraVariants['img-1']!
            .map((variant) => '${variant.engine}|${variant.mode.name}')
            .toSet(),
        hasLength(3),
      );
      expect(state.qualities['img-1'], containsPair('var-1', isNotNull));
      expect(
        state.qualities['img-1'],
        containsPair('var-img-1-horizontal-paddle_v5', isNotNull),
      );
      expect(
        state.qualities['img-1'],
        containsPair('var-img-1-vertical-manga_ocr', isNotNull),
      );
      expect(
        state.qualities['img-1'],
        containsPair('var-img-1-vertical-paddle_v5', isNotNull),
      );
      expect(state.baselineVariants['img-1']?.id, 'var-1');
      final preview = state.previews['img-1']?['var-1'];
      expect(preview, isNotNull);
      expect(preview!.hitCount, greaterThan(0));
      expect(preview.entries.single.headword, '何卒');
      expect(preview.entries.single.snippet, '何卒');
      expect(state.generatedImages, contains('img-1'));
      expect(state.repairs['img-1'], isNotEmpty);
      expect(state.repairBaselineIds['img-1'], 'var-1');
      expect(state.repairs['img-1']!.single.original, 'ニチ');
      expect(state.repairs['img-1']!.single.candidates.single.text, 'ニッポン');
    },
  );

  test(
    'failed run without a result publishes the locally recognized baseline',
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
        baselineVariants: const <String, List<AgentOcrVariant>>{},
        dictionaries: const <DictionaryInfo>[_dictionary],
      );

      final state = container.read(agentOcrVariantsProvider);
      expect(state.errorCode, isNull);
      expect(state.baselineVariants['img-1']?.text, '何卒コンニチハ');
      expect(state.extraVariants['img-1'], hasLength(3));
      expect(state.previews['img-1']?['var-img-1-auto-paddle_v5'], isNotNull);
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
      final switched = first.extraVariants['img-1']!.first;

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

  test('loading and cancellation are tracked per image', () async {
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
    const baselines = <String, List<AgentOcrVariant>>{
      'img-1': <AgentOcrVariant>[_baseline],
      'img-2': <AgentOcrVariant>[_baseline],
    };

    final first = controller.generate(
      images: const <AgentImageInput>[
        AgentImageInput(id: 'img-1', localPath: '/tmp/one.png'),
      ],
      baselineVariants: baselines,
      dictionaries: const <DictionaryInfo>[_dictionary],
    );
    await ocr.started.future;
    expect(
      container.read(agentOcrVariantsProvider).loadingImageIds,
      contains('img-1'),
    );

    final second = controller.generate(
      images: const <AgentImageInput>[
        AgentImageInput(id: 'img-2', localPath: '/tmp/two.png'),
      ],
      baselineVariants: baselines,
      dictionaries: const <DictionaryInfo>[_dictionary],
    );
    expect(
      container.read(agentOcrVariantsProvider).loadingImageIds,
      containsAll(<String>['img-1', 'img-2']),
    );

    controller.cancelImage('img-2');
    expect(
      container.read(agentOcrVariantsProvider).loadingImageIds,
      isNot(contains('img-2')),
    );
    expect(
      container.read(agentOcrVariantsProvider).loadingImageIds,
      contains('img-1'),
    );

    controller.cancelImage('img-1');
    await Future.wait(<Future<void>>[first, second]);
    expect(container.read(agentOcrVariantsProvider).loadingImageIds, isEmpty);
  });

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
