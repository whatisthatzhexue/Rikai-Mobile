import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
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
}
