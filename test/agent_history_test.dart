import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_ocr/rikai_ocr.dart';
import 'package:lexicandy/core/models/agent/agent_analysis.dart';
import 'package:lexicandy/core/models/agent/agent_evidence.dart';
import 'package:lexicandy/core/models/agent/agent_history.dart';
import 'package:lexicandy/core/models/agent/agent_input.dart';
import 'package:lexicandy/core/models/agent/agent_ocr.dart';
import 'package:lexicandy/core/models/agent/agent_pitch.dart';
import 'package:lexicandy/core/models/agent/agent_quote.dart';
import 'package:lexicandy/services/agent/agent_run.dart';
import 'package:lexicandy/services/agent/agent_validator.dart';
import 'package:lexicandy/services/storage/agent_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AgentRunResult _sampleResult({String userText = '何卒'}) {
  const source = AgentSourceInput(
    id: 'src-1',
    kind: AgentSourceKind.imageOcr,
    imageId: 'img-1',
    selectedVariantId: 'var-1',
    variants: <AgentOcrVariant>[
      AgentOcrVariant(
        id: 'var-1',
        engine: 'paddle_v5',
        mode: OcrMode.auto,
        text: '何卒',
        confidence: 0.9,
      ),
      AgentOcrVariant(
        id: 'var-2',
        engine: 'manga_ocr',
        mode: OcrMode.vertical,
        text: '何卒',
        confidence: 0.8,
      ),
    ],
  );
  const quote = AgentQuoteRef(
    id: 'q1',
    sourceId: 'src-1',
    start: 0,
    end: 2,
    text: '何卒',
    origin: AgentQuoteOrigin.ocr,
  );
  const citation = AgentCitation(
    id: 'source-1',
    kind: 'mdict',
    dictionaryId: 'dict-1',
    dictionaryTitle: 'テスト辞典',
    dictionaryOrder: 0,
    entryKey: '何卒',
    matchedKey: '何卒',
    headword: '何卒',
    snippet: 'なにとぞ。どうか。',
    toolCallId: 'call-1',
  );
  const analysis = AgentAnalysis(
    sourceId: 'src-1',
    translation: <AgentTranslation>[
      AgentTranslation(quoteId: 'q1', text: '请务必'),
    ],
    segments: <AgentSegment>[
      AgentSegment(
        id: 'seg-1',
        quoteId: 'q1',
        interpretation: '正式请求对方关照。',
        epistemic: AgentEpistemic.contextInference,
        confidence: 0.8,
      ),
    ],
  );
  const evidence = AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[],
    citations: <AgentCitation>[citation],
  );
  const validation = AgentValidationResult(
    valid: true,
    errors: <String>[],
    citationsUsed: <String>['source-1'],
  );
  return AgentRunResult(
    input: AgentInputEnvelope(
      sessionId: 'session-1',
      mode: AgentMode.strict,
      userText: userText,
      dictionaries: const <AgentDictionaryRef>[
        AgentDictionaryRef(id: 'dict-1', title: 'テスト辞典', order: 0),
      ],
      sources: const <AgentSourceInput>[source],
    ),
    evidence: evidence,
    quotes: const <AgentQuoteRef>[quote],
    analysis: analysis,
    validation: validation,
    sources: const <AgentSourceVersion>[
      AgentSourceVersion(
        id: 'sv-1',
        sourceId: 'src-1',
        origin: AgentQuoteOrigin.ocr,
        text: '何卒',
        imageId: 'img-1',
        variantId: 'var-1',
        engine: 'paddle_v5',
        mode: 'auto',
        confidence: 0.9,
      ),
    ],
    dictionaryProfiles: const <String>['profile-a'],
    ocrQuality: const <String, OcrQuality>{
      'img-1': OcrQuality(
        charCount: 2,
        meaningfulChars: 2,
        duplicateNoiseRatio: 0,
        meanConfidence: 0.9,
        dictionaryHitRate: 0.8,
        contentWords: 2,
      ),
    },
    pitchAccents: const <String, AgentPitchAccent>{
      't1': AgentPitchAccent(accentType: 2, moraCount: 2, moraPattern: 'LH'),
    },
    richOriginalText: '[RUBY=なにとぞ]何卒[/RUBY]',
    richSegmentTexts: const <String>['正式请求对方关照。'],
    richSegmentNotes: const <String>['何卒（なにとぞ）：请务必'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AgentRunResult round-trips structured history data', () {
    final original = _sampleResult();
    final decoded = AgentRunResult.fromJson(agentResultJson(original));

    expect(decoded.input.userText, '何卒');
    expect(decoded.analysis.translation.single.text, '请务必');
    expect(decoded.evidence.citations.single.entryKey, '何卒');
    expect(decoded.quotes.single.text, '何卒');
    expect(decoded.sources.single.variantId, 'var-1');
    expect(decoded.ocrQuality['img-1']?.dictionaryHitRate, 0.8);
    expect(decoded.pitchAccents['t1']?.moraPattern, 'LH');
    expect(decoded.richOriginalText, '[RUBY=なにとぞ]何卒[/RUBY]');
    expect(decoded.richSegmentTexts, <String>['正式请求对方关照。']);
    expect(decoded.richSegmentNotes, <String>['何卒（なにとぞ）：请务必']);
  });

  test('OcrQuality and AgentHistoryEntry round-trip', () {
    const quality = OcrQuality(
      charCount: 4,
      meaningfulChars: 3,
      duplicateNoiseRatio: 0.25,
      meanConfidence: 0.5,
      contentWords: 2,
    );
    final restored = OcrQuality.fromJson(quality.toJson());
    expect(restored.charCount, 4);
    expect(restored.meaningfulChars, 3);
    expect(restored.duplicateNoiseRatio, 0.25);
    expect(restored.meanConfidence, 0.5);
    expect(restored.dictionaryHitRate, isNull);

    final entry = AgentHistoryEntry(
      runId: 'run-1',
      sessionId: 'session-1',
      title: '何卒',
      status: AgentHistoryStatus.done,
      mode: AgentMode.strict,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      finishedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      providerLabel: 'DeepSeek',
      imageCount: 1,
      hasResult: true,
    );
    final entryRestored = AgentHistoryEntry.fromJson(entry.toJson());
    expect(entryRestored.runId, 'run-1');
    expect(entryRestored.status, AgentHistoryStatus.done);
    expect(entryRestored.mode, AgentMode.strict);
    expect(entryRestored.finishedAt?.millisecondsSinceEpoch, 2000);
    expect(entryRestored.imageCount, 1);
  });

  group('AgentStore history', () {
    late AgentStore store;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AgentStore.debugDatabasePath = ':memory:';
      store = AgentStore();
    });

    tearDown(() async {
      await store.close();
      AgentStore.debugDatabasePath = null;
    });

    test('saves, lists, reloads and deletes one run', () async {
      final started = DateTime.fromMillisecondsSinceEpoch(1000);
      final finished = DateTime.fromMillisecondsSinceEpoch(2000);
      await store.saveHistoryRun(
        runId: 'run-1',
        sessionId: 'session-1',
        title: '何卒',
        userText: '何卒',
        status: 'preparing',
        mode: AgentMode.strict,
        providerLabel: 'DeepSeek',
        smallModel: 'small',
        complexModel: 'complex',
        imageCount: 1,
        startedAt: started,
      );
      expect(await store.listHistory(), isEmpty);

      final result = _sampleResult();
      await store.saveHistoryRun(
        runId: 'run-1',
        sessionId: 'session-1',
        title: '何卒',
        userText: '何卒',
        status: 'done',
        mode: AgentMode.strict,
        providerLabel: 'DeepSeek',
        smallModel: 'small',
        complexModel: 'complex',
        imageCount: 1,
        startedAt: started,
        finishedAt: finished,
        result: result,
      );

      final entries = await store.listHistory();
      expect(entries, hasLength(1));
      expect(entries.single.runId, 'run-1');
      expect(entries.single.hasResult, isTrue);
      expect(entries.single.status, AgentHistoryStatus.done);
      final storedRuns = await store.debugRows('agent_runs');
      expect(
        storedRuns.single['result_json'] as String,
        contains('rikai.agent.history-result.v1'),
      );

      final detail = await store.loadHistoryDetail('run-1');
      expect(detail, isNotNull);
      expect(detail!.result, isNotNull);
      expect(detail.result!.analysis.translation.single.text, '请务必');
      expect(detail.result!.input.sources.single.variants, hasLength(2));
      expect(detail.unsupportedFormat, isFalse);

      final encoded = jsonEncode(detail.result!.toJson());
      expect(encoded, isNot(contains('/tmp/')));
      expect(encoded, isNot(contains('file://')));
      expect(encoded, isNot(contains('base64')));

      final variants = await store.debugRows('agent_source_versions');
      expect(variants, hasLength(2));
      expect(
        variants.where((row) => (row['selected'] as int?) == 1),
        hasLength(1),
      );
      final citations = await store.debugRows('agent_citations');
      expect(citations, hasLength(1));
      expect(citations.single['entry_key'], '何卒');

      await store.deleteHistoryRun('run-1');
      expect(await store.listHistory(), isEmpty);
      expect(await store.loadHistoryDetail('run-1'), isNull);
      expect(await store.debugRows('agent_source_versions'), isEmpty);
      expect(await store.debugRows('agent_citations'), isEmpty);
    });

    test('deletes several runs and their children in one batch', () async {
      final started = DateTime.fromMillisecondsSinceEpoch(1000);
      final finished = DateTime.fromMillisecondsSinceEpoch(2000);
      for (final runId in <String>['run-1', 'run-2']) {
        await store.saveHistoryRun(
          runId: runId,
          sessionId: 'session-$runId',
          title: runId,
          userText: runId,
          status: 'done',
          mode: AgentMode.strict,
          providerLabel: 'DeepSeek',
          smallModel: 'small',
          complexModel: 'complex',
          imageCount: 0,
          startedAt: started,
          finishedAt: finished,
          result: runId == 'run-1' ? _sampleResult() : null,
        );
      }
      expect(await store.debugRows('agent_citations'), hasLength(1));
      expect(await store.debugRows('agent_source_versions'), hasLength(2));

      await store.deleteHistoryRuns(<String>['run-1', 'run-2', 'run-1']);

      expect(await store.listHistory(), isEmpty);
      expect(await store.debugRows('agent_citations'), isEmpty);
      expect(await store.debugRows('agent_source_versions'), isEmpty);
      expect(await store.debugRows('agent_sessions'), isEmpty);
    });

    test('marks in-flight runs interrupted and clears history', () async {
      await store.saveHistoryRun(
        runId: 'run-live',
        sessionId: 'session-1',
        title: '何卒',
        userText: '何卒',
        status: 'preparing',
        mode: AgentMode.strict,
        providerLabel: 'DeepSeek',
        smallModel: 'small',
        complexModel: 'complex',
        imageCount: 0,
        startedAt: DateTime.now(),
      );
      expect(await store.markInterruptedRuns(), 1);
      final entries = await store.listHistory();
      expect(entries.single.status, AgentHistoryStatus.interrupted);

      await store.clearHistory();
      expect(await store.listHistory(), isEmpty);
      expect(await store.debugRows('agent_sessions'), isEmpty);
    });
  });
}

Map<String, Object?> agentResultJson(AgentRunResult result) {
  return result.toJson();
}
