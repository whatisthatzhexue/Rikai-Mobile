import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/services/agent/analysis_tag_parser.dart';

void main() {
  test('parses tagged claims and strips leaked internal markers', () {
    const raw = '''
Some prose context_inference（90%） that should be ignored.
[TRANSLATION quote="q1"]请多关照。（90%）[/TRANSLATION]
[SEGMENT type="dictionary_fact" quote="q1"]
[MEANING]这是正式请求。context_inference（90%）
[WORD id="t1"]何卒|なにとぞ|请务必|source-1,source-2[/WORD]
[GRAMMAR id="p1"]固定表达|source-1[/GRAMMAR]
[/SEGMENT]
[SEGMENT type="context_inference" quote="q1"]
[MEANING]也可能只是客套（50%）
[/SEGMENT]
[OPTION id="i1" label="A" citations="source-1"]正式请求[/OPTION]
[UNRESOLVED quote="q1"]缺少更多语境[/UNRESOLVED]
[SUPPLEMENT]补充说明[/SUPPLEMENT]
''';

    final analysis = parseTaggedAnalysis(raw, sourceId: 'src-1');

    expect(analysis, isNotNull);
    expect(analysis!.sourceId, 'src-1');
    expect(analysis.translation.single.text, '请多关照。');
    expect(analysis.segments, hasLength(2));
    expect(analysis.segments.first.epistemic, AgentEpistemic.dictionaryFact);
    expect(analysis.segments.first.confidence, greaterThan(0.9));
    expect(analysis.segments.first.wordNotes.single.reading, 'なにとぞ');
    expect(analysis.segments.first.wordNotes.single.citationIds, <String>[
      'source-1',
      'source-2',
    ]);
    expect(analysis.segments.first.grammarNotes.single.patternId, 'p1');
    expect(
      analysis.segments.first.interpretation,
      isNot(contains('context_inference')),
    );
    expect(analysis.segments.first.interpretation, isNot(contains('90%')));
    expect(analysis.segments.last.epistemic, AgentEpistemic.contextInference);
    expect(analysis.segments.last.interpretation, isNot(contains('50%')));
    expect(analysis.interpretations.single.meaning, '正式请求');
    expect(analysis.unresolved.single.quoteId, 'q1');
    expect(analysis.modelSupplements.single.text, '补充说明');
    expect(
      analysis.citationsUsed,
      containsAll(<String>['source-1', 'source-2']),
    );
  });

  test('accepts structural type aliases and missing reading', () {
    const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="structural_analysis" quote="q1"]
[MEANING]结构说明
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';
    final analysis = parseTaggedAnalysis(raw, sourceId: 'src-1');
    expect(analysis, isNotNull);
    expect(
      analysis!.segments.single.epistemic,
      AgentEpistemic.structuralAnalysis,
    );
    expect(analysis.segments.single.wordNotes.single.reading, isEmpty);
  });

  test(
    'returns null when required translation or segment blocks are absent',
    () {
      expect(
        parseTaggedAnalysis(
          '[TRANSLATION quote="q1"]译文[/TRANSLATION]',
          sourceId: 'src-1',
        ),
        isNull,
      );
      expect(
        parseTaggedAnalysis(
          '[SEGMENT type="fact" quote="q1"][MEANING]解释[/MEANING][/SEGMENT]',
          sourceId: 'src-1',
        ),
        isNull,
      );
    },
  );

  test('parses a standalone NO_ANALYSIS result', () {
    final analysis = parseTaggedAnalysis(
      '[NO_ANALYSIS reason="OCR 文本无法辨认"]',
      sourceId: 'src-1',
    );
    expect(analysis, isNotNull);
    expect(analysis!.noAnalysisReason, 'OCR 文本无法辨认');
    expect(analysis.translation, isEmpty);
    expect(analysis.segments, isEmpty);
    expect(analysis.truncated, isFalse);
  });

  test('rejects NO_ANALYSIS combined with analysis blocks', () {
    const raw = '''
[NO_ANALYSIS reason="无法辨认"]
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"][MEANING]解释[/MEANING][/SEGMENT]
''';
    expect(parseTaggedAnalysis(raw, sourceId: 'src-1'), isNull);
    expect(analysisTagIntegrityErrors(raw), isNotEmpty);
  });

  test('caps segments, duplicate quote/type, options and notes', () {
    final buffer = StringBuffer('[TRANSLATION quote="q1"]译文[/TRANSLATION]\n');
    // The note-heavy segment is first so it is parsed before the segment cap.
    buffer.writeln(
      '[SEGMENT type="structure" quote="q0"][MEANING]词注[/MEANING]'
      '${[for (var index = 1; index <= 25; index++) '[WORD id="t$index"]词$index||义|source-1[/WORD]'].join()}'
      '[/SEGMENT]',
    );
    for (var index = 1; index <= 45; index++) {
      buffer.writeln(
        '[SEGMENT type="fact" quote="q$index"]'
        '[MEANING]解释$index[/MEANING][/SEGMENT]',
      );
    }
    // A second segment with the same quote and type must be dropped.
    buffer.writeln(
      '[SEGMENT type="fact" quote="q1"]'
      '[MEANING]重复[/MEANING][/SEGMENT]',
    );
    for (var index = 1; index <= 10; index++) {
      buffer.writeln('[OPTION id="i$index" label="$index"]选项$index[/OPTION]');
    }

    final analysis = parseTaggedAnalysis(
      buffer.toString(),
      sourceId: 'src-1',
      limits: AgentLimits.standard,
    );
    expect(analysis, isNotNull);
    expect(analysis!.segments.length, AgentLimits.standard.maxSegments);
    expect(
      analysis.segments.first.epistemic,
      AgentEpistemic.structuralAnalysis,
    );
    expect(
      analysis.segments.first.wordNotes.length,
      AgentLimits.standard.maxNotesPerSegment,
    );
    expect(
      analysis.interpretations.length,
      AgentLimits.standard.maxOptionsPerRun,
    );
    expect(analysis.truncated, isTrue);
  });

  test(
    'preserves YOMI annotations and rejects malformed ones structurally',
    () {
      const raw = '''
[TRANSLATION quote="q1"]请多关照[YOMI]（ます）[/YOMI]。[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]正式请求[YOMI]（ます）[/YOMI]。[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[/SEGMENT]
''';
      expect(analysisTagIntegrityErrors(raw), isEmpty);
      final analysis = parseTaggedAnalysis(raw, sourceId: 'src-1');
      expect(analysis, isNotNull);
      expect(analysis!.translation.single.text, contains('[YOMI]（ます）[/YOMI]'));
      expect(
        analysis.segments.single.interpretation,
        contains('[YOMI]（ます）[/YOMI]'),
      );
      expect(
        analysisTagIntegrityErrors(
          '[TRANSLATION quote="q1"]请多关照[YOMI]（ます）[/TRANSLATION]'
          '[SEGMENT type="fact" quote="q1"][MEANING]解释[/MEANING][/SEGMENT]',
        ),
        isNotEmpty,
      );
    },
  );
}
