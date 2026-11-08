import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/agent/agent_quote.dart';
import 'package:rikai_mobile/core/models/dictionary_sample.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

void main() {
  test('input envelope round-trips without exposing an image path', () {
    const envelope = AgentInputEnvelope(
      sessionId: 'sess-1',
      mode: AgentMode.strict,
      userText: '请解释这句话',
      context: '漫画页',
      dictionaries: <AgentDictionaryRef>[
        AgentDictionaryRef(id: 'dict_a', title: 'A', order: 0),
      ],
      sources: <AgentSourceInput>[
        AgentSourceInput(
          id: 'src-1',
          kind: AgentSourceKind.imageOcr,
          imageId: 'img-1',
          selectedVariantId: 'var-1',
          variants: <AgentOcrVariant>[
            AgentOcrVariant(
              id: 'var-1',
              engine: 'paddle_v5',
              mode: OcrMode.auto,
              text: '何卒宜しくお願い致します。',
              confidence: 0.93,
              elapsedMs: 1200,
            ),
          ],
        ),
        AgentSourceInput(
          id: 'src-2',
          kind: AgentSourceKind.userText,
          text: '用户文本',
        ),
      ],
    );

    final json = envelope.toJson();
    expect(json['schema'], 'rikai.agent.input.v1');
    expect(json.containsKey('image_path'), isFalse);
    expect(json.toString().contains('/sdcard'), isFalse);

    final restored = AgentInputEnvelope.fromJson(json);
    expect(restored.mode, AgentMode.strict);
    expect(restored.sources.first.imageId, 'img-1');
    expect(restored.sources.first.selectedVariant!.mode, OcrMode.auto);
    expect(restored.sources.last.text, '用户文本');
  });

  test('evidence bundle preserves citation order and plain snippets', () {
    const bundle = AgentEvidenceBundle(
      sources: <AgentSourceEvidence>[
        AgentSourceEvidence(
          id: 'src-1',
          kind: 'image_ocr',
          text: '何卒',
          tokens: <AgentTokenEvidence>[
            AgentTokenEvidence(
              id: 't1',
              surface: '何卒',
              reading: 'なにとぞ',
              start: 0,
              end: 2,
              content: true,
              lookupCandidates: <String>['何卒', 'なにとぞ'],
            ),
          ],
        ),
      ],
      citations: <AgentCitation>[
        AgentCitation(
          id: 'source-1',
          kind: 'mdict',
          dictionaryId: 'dict_a',
          dictionaryTitle: 'A',
          dictionaryOrder: 0,
          entryKey: '何卒',
          headword: '何卒',
          snippet: 'なにとぞ。どうか。',
          toolCallId: 'call_1',
        ),
      ],
      budget: AgentEvidenceBudget(
        sourceChars: 2,
        uniqueTargets: 1,
        citations: 1,
      ),
    );

    final restored = AgentEvidenceBundle.fromJson(bundle.toJson());
    expect(restored.citations.single.dictionaryOrder, 0);
    expect(restored.citations.single.snippet, 'なにとぞ。どうか。');
    expect(restored.sources.single.tokens.single.lookupCandidates, [
      '何卒',
      'なにとぞ',
    ]);
  });

  test('word notes use bare YOMI and skip identical readings', () {
    const segment = AgentSegment(
      id: 'seg-1',
      quoteId: 'q1',
      interpretation: '正式请求',
      epistemic: AgentEpistemic.dictionaryFact,
      wordNotes: <AgentWordNote>[
        AgentWordNote(
          tokenId: 't1',
          surface: '何卒',
          reading: 'なにとぞ',
          sense: '请务必',
        ),
        AgentWordNote(
          tokenId: 't2',
          surface: 'ます',
          reading: 'ます',
          sense: '助动词',
        ),
        AgentWordNote(tokenId: 't3', surface: '今日', reading: '', sense: '今天'),
      ],
    );

    expect(
      agentSegmentNotesSource(segment),
      '何卒[YOMI]なにとぞ[/YOMI]：请务必\nます：助动词\n今日：今天',
    );
  });

  test('analysis round-trips structured claims and epistemic classes', () {
    const analysis = AgentAnalysis(
      sourceId: 'src-1',
      translation: <AgentTranslation>[
        AgentTranslation(quoteId: 'q1', text: '请多关照。'),
      ],
      segments: <AgentSegment>[
        AgentSegment(
          id: 'seg-1',
          quoteId: 'q1',
          literal: '何卒宜しくお願い致します。',
          interpretation: '正式请求',
          epistemic: AgentEpistemic.dictionaryFact,
          wordNotes: <AgentWordNote>[
            AgentWordNote(
              tokenId: 't1',
              surface: '何卒',
              reading: 'なにとぞ',
              sense: '请务必',
              citationIds: <String>['source-1'],
            ),
          ],
          grammarNotes: <AgentGrammarNote>[
            AgentGrammarNote(
              patternId: 'p1',
              explanation: '谦让表达',
              citationIds: <String>['source-1'],
            ),
          ],
        ),
      ],
      interpretations: <AgentInterpretation>[
        AgentInterpretation(
          id: 'i1',
          label: 'A',
          meaning: '正式请求',
          confidence: 0.8,
          citationIds: <String>['source-1'],
        ),
      ],
    );

    final restored = AgentAnalysis.fromJson(analysis.toJson());
    expect(restored.segments.single.epistemic, AgentEpistemic.dictionaryFact);
    expect(restored.segments.single.wordNotes.single.sense, '请务必');
    expect(restored.translation.single.quoteId, 'q1');
    expect(restored.noAnalysisReason, isEmpty);
    expect(restored.truncated, isFalse);
  });

  test('NO_ANALYSIS and truncated flags round-trip', () {
    const analysis = AgentAnalysis(
      sourceId: 'src-1',
      noAnalysisReason: 'OCR 文本无法辨认',
      truncated: true,
    );
    final restored = AgentAnalysis.fromJson(analysis.toJson());
    expect(restored.noAnalysisReason, 'OCR 文本无法辨认');
    expect(restored.truncated, isTrue);
    expect(restored.translation, isEmpty);
    expect(restored.segments, isEmpty);
  });

  test('dictionary profile and quote round-trip', () {
    const profile = DictionaryProfile(
      dictionaryId: 'dict_a',
      title: 'A',
      kind: '国語辞典',
      intro: '国語辞典のサンプル。',
      languagePairs: <DictionaryLanguagePair>[
        DictionaryLanguagePair(source: 'ja', target: 'ja', confidence: 0.8),
      ],
      coverage: DictionaryCoverage(
        sampleEntries: 12,
        entryCount: 100,
        headwordScripts: <String>['han', 'hiragana'],
        definitionScripts: <String>['han', 'hiragana'],
        featureCount: 2,
        sampleTruncated: true,
        unsampledProbeCount: 4,
      ),
      entryStructure: DictionaryEntryStructure(
        headwordFields: <String>['見出し'],
        definitionFields: <String>['語義'],
        hasRuby: true,
      ),
      searchBehavior: DictionarySearchBehavior(
        exactForms: <String>['漢字', 'かな'],
        prefixSuggestions: true,
      ),
      confidence: 0.8,
    );
    final restoredProfile = DictionaryProfile.fromJson(profile.toJson());
    expect(restoredProfile.entryStructure.hasRuby, isTrue);
    expect(restoredProfile.intro, '国語辞典のサンプル。');
    expect(restoredProfile.languagePairs.single.label, 'ja→ja');
    expect(restoredProfile.coverage.sampleEntries, 12);
    expect(restoredProfile.coverage.featureCount, 2);
    expect(restoredProfile.coverage.sampleTruncated, isTrue);
    expect(restoredProfile.coverage.unsampledProbeCount, 4);

    const quote = AgentQuoteRef(
      id: 'q1',
      sourceId: 'src-1',
      start: 0,
      end: 2,
      text: '何卒',
      origin: AgentQuoteOrigin.ocr,
    );
    expect(AgentQuoteRef.fromJson(quote.toJson()).text, '何卒');
  });

  test('run telemetry round-trips content-free counters', () {
    const telemetry = AgentRunTelemetry(
      llmCalls: 3,
      analysisCalls: 1,
      coverageCalls: 1,
      repairCalls: 1,
      languageRepairCalls: 0,
      formattingCalls: 1,
      inputChars: 100,
      outputChars: 40,
      reasoningChars: 5,
      llmElapsedMs: 30,
      elapsedMs: 50,
      citationCount: 3,
      adoptedCitationCount: 2,
      targetsWithCitations: 2,
      targetCount: 4,
      httpAttempts: 3,
      analysisTtftMs: 1200,
      analysisPrefillChars: 5000,
    );

    final restored = AgentRunTelemetry.fromJson(telemetry.toJson());
    expect(restored.llmCalls, 3);
    expect(restored.analysisCalls, 1);
    expect(restored.coverageCalls, 1);
    expect(restored.repairCalls, 1);
    expect(restored.formattingCalls, 1);
    expect(restored.inputChars, 100);
    expect(restored.outputChars, 40);
    expect(restored.httpAttempts, 3);
    expect(restored.analysisTtftMs, 1200);
    expect(restored.analysisPrefillChars, 5000);
    expect(restored.citationCoverage, 0.5);
    expect(restored.repairRate, 1);
  });

  test('dictionary sample round-trips plain-text features', () {
    const sample = DictionarySample(
      dictionaryId: 'dict_a',
      metadata: DictionarySampleMetadata(
        title: 'A',
        entryCount: 10,
        hasMdd: true,
      ),
      entries: <DictionarySampleEntry>[
        DictionarySampleEntry(
          matchedKey: '何卒',
          headword: '何卒',
          snippet: 'なにとぞ',
          features: DictionarySampleFeatures(hasRuby: true, tagCount: 3),
        ),
      ],
      truncated: true,
      unsampledProbes: <String>['は', 'です'],
    );
    final restored = DictionarySample.fromJson(sample.toJson());
    expect(restored.entries.single.features.hasRuby, isTrue);
    expect(restored.entries.single.snippet, 'なにとぞ');
    expect(restored.truncated, isTrue);
    expect(restored.unsampledProbes, <String>['は', 'です']);
    expect(sample.toPromptJson().containsKey('truncated'), isFalse);
    expect(sample.toPromptJson().containsKey('unsampled_probes'), isFalse);
  });

  test('provider base URLs require HTTPS and a host', () {
    expect(agentBaseUrlError('https://api.deepseek.com'), isNull);
    expect(agentBaseUrlError('http://api.deepseek.com'), contains('HTTPS'));
    expect(agentBaseUrlError(''), contains('Base URL'));
    expect(agentBaseUrlError('not a url'), contains('有效'));
    expect(agentBaseUrlError('https://user:pass@example.com'), contains('账号'));
  });

  test('provider presets fill known service addresses', () {
    expect(AgentProviderPreset.deepSeek.label, 'DeepSeek');
    expect(
      AgentProviderPreset.deepSeek.defaultBaseUrl,
      'https://api.deepseek.com/',
    );
    expect(
      AgentProviderPreset.anthropic.defaultBaseUrl,
      'https://api.anthropic.com/',
    );
    expect(AgentProviderPreset.forConfig(null), AgentProviderPreset.deepSeek);

    const anthropic = AgentProviderConfig(
      id: 'a',
      kind: AgentProviderKind.anthropic,
      displayName: 'Claude',
      baseUrl: 'https://api.anthropic.com',
      smallModel: 'small',
      complexModel: 'large',
    );
    expect(
      AgentProviderPreset.forConfig(anthropic),
      AgentProviderPreset.anthropic,
    );

    const custom = AgentProviderConfig(
      id: 'c',
      kind: AgentProviderKind.openAiCompatible,
      displayName: 'Custom',
      baseUrl: 'https://example.com/v1',
      smallModel: 'small',
      complexModel: 'large',
    );
    expect(AgentProviderPreset.forConfig(custom), AgentProviderPreset.custom);
  });

  test('provider config preserves the optional max output tokens', () {
    const config = AgentProviderConfig(
      id: 'p1',
      kind: AgentProviderKind.openAiCompatible,
      displayName: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/',
      smallModel: 'small',
      complexModel: 'large',
      maxOutputTokens: 4096,
    );
    final json = config.toJson();
    expect(json['max_output_tokens'], 4096);
    expect(
      (json['capabilities'] as Map<String, Object?>)['max_output_tokens'],
      4096,
    );
    expect(AgentProviderConfig.fromJson(json).maxOutputTokens, 4096);

    final legacyCapabilities = Map<String, Object?>.of(
      json['capabilities'] as Map<String, Object?>,
    )..remove('max_output_tokens');
    final legacy = Map<String, Object?>.of(json)
      ..remove('max_output_tokens')
      ..['capabilities'] = legacyCapabilities;
    expect(AgentProviderConfig.fromJson(legacy).maxOutputTokens, 0);

    final dbStyle = Map<String, Object?>.of(legacy)
      ..['capabilities'] = <String, Object?>{
        'streaming': true,
        'max_output_tokens': 2048,
      };
    expect(AgentProviderConfig.fromJson(dbStyle).maxOutputTokens, 2048);
  });
}
