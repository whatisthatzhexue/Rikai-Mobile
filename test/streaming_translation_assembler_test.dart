import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/streaming_translation_assembler.dart';

void main() {
  test('emits only complete translations and tolerates chunk boundaries', () {
    final previews = <String>[];
    final assembler = StreamingTranslationAssembler(
      quoteIds: const <String>{'q1', 'q2'},
      onPreview: previews.add,
    );

    assembler.add('[TRANSLATION quote="q1"]请多');
    expect(previews, isEmpty);
    assembler.add('关照。[/TRANSL');
    expect(previews, isEmpty);
    assembler.add('ATION]\n[SEGMENT');
    expect(previews, ['请多关照。']);
    assembler.add(' type="fact" quote="q2"]');
    expect(previews, ['请多关照。']);
    assembler.add('[TRANSLATION quote="q2"]第二段[/TRANSLATION]');
    expect(previews, ['请多关照。', '第二段']);
  });

  test('ignores unknown quote ids and empty bodies', () {
    final previews = <String>[];
    final assembler = StreamingTranslationAssembler(
      quoteIds: const <String>{'q1'},
      onPreview: previews.add,
    );

    assembler.add('[TRANSLATION quote="missing"]ignore[/TRANSLATION]');
    assembler.add('[TRANSLATION quote="q1"]  [/TRANSLATION]');
    assembler.flush();
    expect(previews, isEmpty);
  });

  test('deduplicates replayed prefix blocks after a continuation reset', () {
    final previews = <String>[];
    final assembler = StreamingTranslationAssembler(
      quoteIds: const <String>{'q1'},
      onPreview: previews.add,
    );

    assembler.add('[TRANSLATION quote="q1"]译文[/TRANSLATION]\n');
    expect(previews, ['译文']);

    assembler.reset('[TRANSLATION quote="q1"]译文[/TRANSLATION]\n');
    assembler.add('[TRANSLATION quote="q1"]译文[/TRANSLATION]\n');
    expect(previews, ['译文']);
  });

  test('does not expose unclosed translation blocks', () {
    final previews = <String>[];
    final assembler = StreamingTranslationAssembler(
      quoteIds: const <String>{'q1'},
      onPreview: previews.add,
    );

    assembler.add('[TRANSLATION quote="q1"]没有结束');
    assembler.flush();
    expect(previews, isEmpty);
  });
}
