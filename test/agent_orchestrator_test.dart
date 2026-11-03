import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/models/lookup_request.dart';
import 'package:rikai_mobile/core/models/token.dart';
import 'package:rikai_mobile/services/agent/agent_orchestrator.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/citation_registry.dart';
import 'package:rikai_mobile/services/agent/grammar_patterns.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/ports/lookup_port.dart';
import 'package:rikai_mobile/services/agent/ports/ocr_port.dart';
import 'package:rikai_mobile/services/agent/ports/tokenize_port.dart';
import 'package:rikai_mobile/services/agent/providers/fake_provider.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const _dictionary = DictionaryInfo(
  id: 'dict_a',
  title: 'A',
  mdxPath: '/a.mdx',
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

const _analysisDetailedRich = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]今[YOMI]（いま）[/YOMI]表示现在[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

const _analysisWithYomi = '''
[TRANSLATION quote="q1"]请多关照：何卒[YOMI]（なにとぞ）[/YOMI]。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';

const _analysisWithoutCitation = '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]无依据[/MEANING]
[/SEGMENT]
''';

const _analysisJapanese = '''
[TRANSLATION quote="q1"]どういたしまして。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式な依頼です[/MEANING]
[WORD id="t1"]何卒||なにとぞ|source-1[/WORD]
[/SEGMENT]
''';

const _analysisEnglish = '''
[TRANSLATION quote="q1"]Please treat me well.[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]A formal request expression[/MEANING]
[WORD id="t1"]何卒||formal request|source-1[/WORD]
[/SEGMENT]
''';

class _FakeOcr implements OcrPort {
  int calls = 0;

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
    calls++;
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

/// First response is returned immediately; the follow-up repair call blocks
/// until the test releases it, proving the provisional result was emitted
/// before the second model round-trip completed.
class _BlockingRepairProvider implements LlmPort {
  _BlockingRepairProvider({required this.firstResponse});

  final String firstResponse;
  final Completer<void> repairStarted = Completer<void>();
  final Completer<void> releaseRepair = Completer<void>();
  int calls = 0;

  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    calls++;
    if (calls == 1) {
      yield LlmEvent(type: LlmEventType.textDelta, text: firstResponse);
      yield LlmEvent.done();
      return;
    }
    if (!repairStarted.isCompleted) repairStarted.complete();
    await releaseRepair.future;
    yield LlmEvent(type: LlmEventType.textDelta, text: _analysisTagged);
    yield LlmEvent.done();
  }
}

AgentOrchestrator _orchestrator({
  required LlmPort provider,
  _FakeOcr? ocr,
  AgentLimits limits = const AgentLimits(
    maxCoverageFallback: 0,
    enableRichTextPostProcess: false,
  ),
}) {
  return AgentOrchestrator(
    ocrPort: ocr ?? _FakeOcr(),
    tokenizePort: _FakeTokenize(),
    lookupPort: _FakeLookup(),
    grammar: GrammarPatternCatalog(const <GrammarPattern>[]),
    citations: CitationRegistry(),
    llmFactory: (_) => provider,
    // Most tests isolate analysis; F7 coverage/rich-text tests opt in.
    limits: limits,
  );
}

void main() {
  test('runs the fixed pipeline and returns cited evidence', () async {
    final provider = FakeProvider(responseText: _analysisTagged);
    final stages = <AgentStage>[];
    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
      onStage: (stage, message) => stages.add(stage),
    );

    expect(result.analysis.sourceId, 'src-1');
    expect(result.citations, hasLength(1));
    expect(result.validation.valid, isTrue);
    expect(result.quotes.single.text, '何卒');
    expect(stages, contains(AgentStage.done));
    expect(provider.requests, hasLength(1));
    final requestText = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(requestText.contains('何卒'), isTrue);
    expect(requestText.contains('/sdcard'), isFalse);
  });

  test('OCR image paths are never placed in the provider request', () async {
    final provider = FakeProvider(responseText: _analysisTagged);
    final ocr = _FakeOcr();
    await _orchestrator(provider: provider, ocr: ocr).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        images: <AgentImageInput>[
          AgentImageInput(
            id: 'img-1',
            localPath: '/sdcard/Download/private-page.jpg',
          ),
        ],
      ),
    );

    expect(ocr.calls, 1);
    final requestText = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(requestText.contains('img-1'), isTrue);
    expect(requestText.contains('/sdcard'), isFalse);
    expect(requestText.contains('private-page.jpg'), isFalse);
  });

  test(
    'image plus instruction keeps the instruction out of evidence sources',
    () async {
      final provider = FakeProvider(responseText: _analysisTagged);
      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '请解释这句话',
          images: <AgentImageInput>[
            AgentImageInput(
              id: 'img-1',
              localPath: '/sdcard/Download/page.jpg',
            ),
          ],
        ),
      );

      expect(result.input.userText, '请解释这句话');
      expect(result.input.sources, hasLength(1));
      expect(result.evidence.sources, hasLength(1));
      expect(result.evidence.sources.single.kind, 'image_ocr');
    },
  );

  test(
    'strict validation failure is repaired without redoing OCR/lookup',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_analysisWithoutCitation, _analysisTagged],
      );

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
      );

      expect(result.validation.valid, isTrue);
      expect(result.analysis.segments, isNotEmpty);
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt.contains('Validation errors'), isTrue);
      expect(repairPrompt.contains('Previous output'), isTrue);
    },
  );

  test(
    'emits a displayable result before a slow validation repair finishes',
    () async {
      final provider = _BlockingRepairProvider(
        firstResponse: _analysisWithoutCitation,
      );
      final previews = <AgentRunResult>[];
      final runFuture = _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
        onProvisionalResult: previews.add,
      );

      await provider.repairStarted.future;
      expect(previews, isNotEmpty);
      expect(previews.first.validation.valid, isFalse);
      expect(previews.first.analysis.translation.single.text, '请多关照。');

      provider.releaseRepair.complete();
      final result = await runFuture;
      expect(result.validation.valid, isTrue);
      expect(provider.calls, 2);
    },
  );

  test(
    'emits the valid analysis before a slow language repair finishes',
    () async {
      final provider = _BlockingRepairProvider(
        firstResponse: _analysisJapanese,
      );
      final previews = <AgentRunResult>[];
      final runFuture = _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
        onProvisionalResult: previews.add,
      );

      await provider.repairStarted.future;
      expect(previews, isNotEmpty);
      expect(previews.first.validation.valid, isTrue);
      expect(previews.first.analysis.translation.single.text, 'どういたしまして。');

      provider.releaseRepair.complete();
      final result = await runFuture;
      expect(result.validation.valid, isTrue);
      expect(result.analysis.translation.single.text, '请多关照。');
      expect(provider.calls, 2);
    },
  );

  test(
    'tagged output repairs a broken format without redoing evidence',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[
          'This is not a tagged response.',
          '''
[TRANSLATION quote="q1"]请多关照。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''',
        ],
      );

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
      );

      expect(result.validation.valid, isTrue);
      expect(result.analysis.translation.single.text, '请多关照。');
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt, contains('FORMAT CORRECTION TASK'));
      expect(repairPrompt, contains('Previous output'));
    },
  );

  test(
    'orphan tag triggers one format repair even when content parses',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[
          '$_analysisTagged[/SEGMENT]',
          _analysisTagged,
        ],
      );

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
      );

      expect(result.validation.valid, isTrue);
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt, contains('多余的结束标签 [/SEGMENT]'));
    },
  );

  test('unrepaired tag integrity failure is reported, not accepted', () async {
    final provider = FakeProvider(responseText: '$_analysisTagged[/SEGMENT]');

    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
    );

    expect(result.validation.valid, isFalse);
    expect(
      result.validation.errors.any(
        (error) => error.contains('多余的结束标签 [/SEGMENT]'),
      ),
      isTrue,
    );
    expect(result.analysis.translation, isNotEmpty);
    expect(provider.requests, hasLength(2));
  });

  test('unrepaired output is salvaged instead of being thrown away', () async {
    final provider = FakeProvider(responseText: _analysisWithoutCitation);

    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        userText: '何卒',
      ),
    );

    expect(result.validation.valid, isFalse);
    expect(result.validation.errors, isNotEmpty);
    expect(result.analysis.translation, isNotEmpty);
    expect(result.analysis.segments, isEmpty);
    expect(result.analysis.unresolved, isNotEmpty);
    expect(provider.requests, hasLength(2));
  });

  test('salvaged results still receive rich-text formatting', () async {
    const rich = '[BOLD]何卒[/BOLD]';
    final provider = FakeProvider(
      responseSequence: <String>[
        _analysisWithoutCitation,
        _analysisWithoutCitation,
        rich,
      ],
    );
    final stages = <AgentStage>[];

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
          onStage: (stage, message) => stages.add(stage),
        );

    expect(result.validation.valid, isFalse);
    expect(result.richOriginalText, rich);
    expect(stages, contains(AgentStage.formatting));
    expect(provider.requests, hasLength(3));
  });

  test(
    'wrong-language fields trigger one language repair and use the result',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_analysisJapanese, _analysisTagged],
      );

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
      );

      expect(result.analysis.translation.single.text, '请多关照。');
      expect(result.warnings, isEmpty);
      expect(provider.requests, hasLength(2));
      final repairPrompt = provider.requests.last.messages
          .map((message) => message.text)
          .join('\n');
      expect(repairPrompt, contains('LANGUAGE CORRECTION TASK'));
      expect(repairPrompt, contains('Fields needing language correction'));
    },
  );

  test(
    'a still-wrong language repair keeps the result with a warning',
    () async {
      final provider = FakeProvider(
        responseSequence: <String>[_analysisJapanese, _analysisJapanese],
      );

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
        ),
      );

      expect(result.analysis.translation, isNotEmpty);
      expect(result.warnings, contains('部分内容未按设置语言输出'));
      expect(provider.requests, hasLength(2));
    },
  );

  test(
    'an English response language accepts English fields without repair',
    () async {
      final provider = FakeProvider(responseText: _analysisEnglish);

      final result = await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '何卒',
          responseLanguage: AgentResponseLanguage.english,
        ),
      );

      expect(result.analysis.translation.single.text, 'Please treat me well.');
      expect(result.warnings, isEmpty);
      expect(provider.requests, hasLength(1));
    },
  );

  test('reuses prepared OCR variants without repeating recognition', () async {
    final ocr = _FakeOcr();
    final provider = FakeProvider(responseText: _analysisTagged);
    const baseline = AgentOcrVariant(
      id: 'var-1',
      engine: 'paddle_v5',
      mode: OcrMode.auto,
      text: '何卒',
      confidence: 0.9,
    );
    const repaired = AgentOcrVariant(
      id: 'repair-1',
      engine: 'dictionary_repair',
      mode: OcrMode.auto,
      text: '何卒',
      confidence: 0.9,
      origin: AgentQuoteOrigin.dictionaryRepair,
    );

    final result = await _orchestrator(provider: provider, ocr: ocr).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        images: <AgentImageInput>[
          AgentImageInput(
            id: 'img-1',
            localPath: '/never-used.png',
            variants: <AgentOcrVariant>[baseline, repaired],
            selectedVariantId: 'repair-1',
          ),
        ],
      ),
    );

    expect(ocr.calls, 0);
    expect(result.input.sources, hasLength(1));
    expect(result.input.sources.single.selectedVariantId, 'repair-1');
    expect(result.input.sources.single.variants, hasLength(2));
    expect(result.sources.single.origin, AgentQuoteOrigin.dictionaryRepair);
    expect(result.quotes.single.origin, AgentQuoteOrigin.dictionaryRepair);
    expect(result.ocrQuality['img-1'], isNotNull);
    final requestText = provider.requests.single.messages
        .map((message) => message.text)
        .join('\n');
    expect(requestText.contains('/never-used.png'), isFalse);
    expect(requestText.contains('file://'), isFalse);
  });

  test(
    'prepared OCR variants are capped at four with the selected kept',
    () async {
      final variants = <AgentOcrVariant>[
        for (var index = 0; index < 5; index++)
          AgentOcrVariant(
            id: 'v$index',
            engine: 'paddle_v5',
            mode: OcrMode.auto,
            text: '何卒',
            confidence: 0.9,
          ),
      ];
      final result =
          await _orchestrator(
            provider: FakeProvider(responseText: _analysisTagged),
          ).run(
            AgentRunRequest(
              sessionId: 's1',
              mode: AgentMode.strict,
              dictionaries: const <DictionaryInfo>[_dictionary],
              provider: _provider,
              images: <AgentImageInput>[
                AgentImageInput(
                  id: 'img-1',
                  localPath: '/never-used.png',
                  variants: variants,
                  selectedVariantId: 'v4',
                ),
              ],
            ),
          );

      expect(
        result.input.sources.single.variants.map((variant) => variant.id),
        <String>['v4', 'v0', 'v1', 'v2'],
      );
      expect(result.input.sources.single.selectedVariantId, 'v4');
    },
  );

  test('multi-image runs expose quotes from every source', () async {
    const first = AgentOcrVariant(
      id: 'v1',
      engine: 'paddle_v5',
      mode: OcrMode.horizontal,
      text: '一枚目の文章です。',
      confidence: 0.9,
    );
    const second = AgentOcrVariant(
      id: 'v2',
      engine: 'paddle_v5',
      mode: OcrMode.horizontal,
      text: '二枚目の文章です。',
      confidence: 0.9,
    );
    final provider = FakeProvider(responseText: _analysisTagged);

    final result = await _orchestrator(provider: provider).run(
      const AgentRunRequest(
        sessionId: 's1',
        mode: AgentMode.strict,
        dictionaries: <DictionaryInfo>[_dictionary],
        provider: _provider,
        images: <AgentImageInput>[
          AgentImageInput(
            id: 'img-1',
            localPath: '/never-used-1.png',
            variants: <AgentOcrVariant>[first],
            selectedVariantId: 'v1',
          ),
          AgentImageInput(
            id: 'img-2',
            localPath: '/never-used-2.png',
            variants: <AgentOcrVariant>[second],
            selectedVariantId: 'v2',
          ),
        ],
      ),
    );

    expect(result.quotes.map((quote) => quote.sourceId).toSet(), <String>{
      'src-1',
      'src-2',
    });
    expect(
      result.quotes.map((quote) => quote.text),
      containsAll(<String>['一枚目の文章です。', '二枚目の文章です。']),
    );
    expect(result.quotes.map((quote) => quote.id).toSet(), hasLength(2));
  });

  test(
    'analysis prompt carries the selected source once and omits internal fields',
    () async {
      const sourceText = '今日は良い天気ですね。';
      const variant = AgentOcrVariant(
        id: 'v1',
        engine: 'paddle_v5',
        mode: OcrMode.auto,
        text: sourceText,
        confidence: 0.93,
      );
      final provider = FakeProvider(responseText: _analysisTagged);

      await _orchestrator(provider: provider).run(
        const AgentRunRequest(
          sessionId: 's1',
          mode: AgentMode.strict,
          dictionaries: <DictionaryInfo>[_dictionary],
          provider: _provider,
          userText: '解释',
          images: <AgentImageInput>[
            AgentImageInput(
              id: 'img-1',
              localPath: '/never-used.png',
              variants: <AgentOcrVariant>[variant],
              selectedVariantId: 'v1',
            ),
          ],
        ),
      );

      final requestText = provider.requests.single.messages
          .map((message) => message.text)
          .join('\n');
      expect(requestText, contains('"selected_variant_id":"v1"'));
      expect(requestText, isNot(contains('"variants"')));
      expect(requestText, isNot(contains('"lookup_candidates"')));
      expect(requestText, isNot(contains('"tool_call_id"')));
      expect(requestText, isNot(contains('"budget"')));
      // One copy in the input envelope, one in the available quote. The
      // evidence projection must not repeat the source text.
      expect(
        RegExp(RegExp.escape(sourceText)).allMatches(requestText).length,
        2,
      );
    },
  );

  test('rich-text formatting can complete after the core result', () async {
    const rich = '[BOLD]何卒[/BOLD]';
    const segmentRich = '[BOLD]正式请求[/BOLD]';
    const notesRich = '[BOLD]何卒：请务必[/BOLD]';
    final provider = FakeProvider(
      responseSequence: <String>[_analysisTagged, rich, segmentRich, notesRich],
    );
    final ready = Completer<AgentRichTextOutputs>();

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
          onRichTextReady: (outputs) => ready.complete(outputs),
        );

    // The core result is delivered before display-only formatting finishes.
    expect(result.richOriginalText, isNull);
    expect(result.richSegmentTexts, isEmpty);
    final outputs = await ready.future.timeout(const Duration(seconds: 5));
    expect(outputs.originalText, rich);
    expect(outputs.segmentTexts, <String>[segmentRich]);
    expect(outputs.segmentNotes, <String>[notesRich]);
    expect(provider.requests, hasLength(4));
  });

  test('rich-text post-processing accepts only exact original text', () async {
    const rich = '[BOLD]何卒[/BOLD]';
    const segmentRich = '[BOLD]正式请求[/BOLD]';
    const notesRich = '[BOLD]何卒：请务必[/BOLD]';
    final provider = FakeProvider(
      responseSequence: <String>[_analysisTagged, rich, segmentRich, notesRich],
    );
    final stages = <AgentStage>[];

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
          onStage: (stage, message) => stages.add(stage),
        );

    expect(result.richOriginalText, rich);
    expect(result.richSegmentTexts, <String>[segmentRich]);
    expect(result.richSegmentNotes, <String>[notesRich]);
    expect(stages, contains(AgentStage.formatting));
    expect(provider.requests, hasLength(4));
  });

  test('formats the original section and each segment separately', () async {
    const originalRich = '[BOLD]何卒[/BOLD]';
    const segmentRich = '[RUBY=いま]今[/RUBY][BOLD]表示现在[/BOLD]';
    const notesRich = '[BOLD]何卒：请务必[/BOLD]';
    final provider = FakeProvider(
      responseSequence: <String>[
        _analysisDetailedRich,
        originalRich,
        segmentRich,
        notesRich,
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.richOriginalText, originalRich);
    expect(result.richSegmentTexts, <String>[segmentRich]);
    expect(result.richSegmentNotes, <String>[notesRich]);
    expect(provider.requests, hasLength(4));
  });

  test('rich-text post-processing annotates the original quote', () async {
    const rich = '[RUBY=なにとぞ]何卒[/RUBY]';
    const segmentRich = '[BOLD]正式请求[/BOLD]';
    const notesRich = '[BOLD]何卒：请务必[/BOLD]';
    final provider = FakeProvider(
      responseSequence: <String>[
        _analysisWithYomi,
        rich,
        segmentRich,
        notesRich,
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.richOriginalText, rich);
    expect(result.richSegmentTexts, <String>[segmentRich]);
    expect(result.richSegmentNotes, <String>[notesRich]);
    expect(provider.requests, hasLength(4));
  });

  test('rich-text fallback converts retained YOMI locally', () async {
    final provider = FakeProvider(
      responseSequence: <String>[
        _analysisDetailedRich,
        '[BOLD]何卒[/BOLD]',
        'not a valid tagged response',
        '何卒：请务必',
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
            richTextConcurrency: 1,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.richSegmentTexts.single, contains('[RUBY=いま]今[/RUBY]'));
    expect(result.richSegmentTexts.single, isNot(contains('（いま）')));
    expect(provider.requests, hasLength(4));
  });

  test('rich-text output that changes the text falls back to plain', () async {
    final provider = FakeProvider(
      responseSequence: <String>[
        _analysisTagged,
        '[BOLD]何卒！[/BOLD]',
        '正式请求',
        '何卒：请务必',
      ],
    );

    final result =
        await _orchestrator(
          provider: provider,
          limits: const AgentLimits(
            maxCoverageFallback: 0,
            enableRichTextPostProcess: true,
          ),
        ).run(
          const AgentRunRequest(
            sessionId: 's1',
            mode: AgentMode.strict,
            dictionaries: <DictionaryInfo>[_dictionary],
            provider: _provider,
            userText: '何卒',
          ),
        );

    expect(result.richOriginalText, isNull);
    expect(result.richSegmentTexts, <String>['正式请求']);
    expect(result.richSegmentNotes, <String>['何卒：请务必']);
    expect(provider.requests, hasLength(4));
  });
}
