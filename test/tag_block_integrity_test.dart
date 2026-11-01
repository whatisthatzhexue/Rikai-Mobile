import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/analysis_tag_parser.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_profile_tag_parser.dart';

void main() {
  group('analysis tag integrity', () {
    test('accepts complete, correctly nested blocks', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]解释[/MEANING]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
[GRAMMAR id="p1"]固定表达|source-1[/GRAMMAR]
[/SEGMENT]
[OPTION id="i1" label="A" citations="source-1"]备选[/OPTION]
[UNRESOLVED quote="q1"]语境不足[/UNRESOLVED]
[SUPPLEMENT]补充[/SUPPLEMENT]
''';
      expect(analysisTagIntegrityErrors(raw), isEmpty);
    });

    test('reports a truncated block', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]解释
''';
      final errors = analysisTagIntegrityErrors(raw);
      expect(errors.any((error) => error.contains('[SEGMENT] 缺少结束标签')), isTrue);
      expect(errors.any((error) => error.contains('[MEANING] 缺少结束标签')), isTrue);
    });

    test('reports an orphan close tag', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[/SEGMENT]
''';
      expect(analysisTagIntegrityErrors(raw), contains('多余的结束标签 [/SEGMENT]'));
    });

    test('reports children outside their required parent', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[WORD id="t1"]何卒||请务必|source-1[/WORD]
''';
      expect(
        analysisTagIntegrityErrors(raw),
        contains('标签 [WORD] 必须位于 [SEGMENT] 内'),
      );
    });

    test('reports duplicate single-instance tags', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]第一段[/MEANING]
[MEANING]第二段[/MEANING]
[/SEGMENT]
''';
      expect(
        analysisTagIntegrityErrors(raw),
        contains('标签 [SEGMENT] 内出现重复的 [MEANING]'),
      );
    });

    test('reports a nested root-only block', () {
      const raw = '''
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[SEGMENT type="fact" quote="q1"]
[MEANING]解释[/MEANING]
[/SEGMENT]
[/SEGMENT]
''';
      expect(
        analysisTagIntegrityErrors(raw),
        contains('标签 [SEGMENT] 只能位于顶层，不能嵌套在 [SEGMENT] 内'),
      );
    });
  });

  group('dictionary profile tag integrity', () {
    test('accepts complete profile blocks', () {
      const raw = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[KIND]国語辞典[/KIND]
[STRENGTHS]多义项|例句丰富[/STRENGTHS]
[/PROFILE]
[PROFILE]
[ID]dict_b[/ID]
[KIND]類語辞典[/KIND]
[/PROFILE]
''';
      expect(dictionaryProfileTagIntegrityErrors(raw), isEmpty);
    });

    test('reports an unclosed profile block', () {
      const raw = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A
''';
      final errors = dictionaryProfileTagIntegrityErrors(raw);
      expect(errors.any((error) => error.contains('[PROFILE] 缺少结束标签')), isTrue);
      expect(errors.any((error) => error.contains('[TITLE] 缺少结束标签')), isTrue);
    });

    test('reports fields outside a profile block', () {
      const raw = '''
[PROFILE]
[ID]dict_a[/ID]
[/PROFILE]
[TITLE]A[/TITLE]
''';
      expect(
        dictionaryProfileTagIntegrityErrors(raw),
        contains('标签 [TITLE] 必须位于 [PROFILE] 内'),
      );
    });

    test('reports duplicate profile fields', () {
      const raw = '''
[PROFILE]
[ID]dict_a[/ID]
[TITLE]A[/TITLE]
[TITLE]B[/TITLE]
[/PROFILE]
''';
      expect(
        dictionaryProfileTagIntegrityErrors(raw),
        contains('标签 [PROFILE] 内出现重复的 [TITLE]'),
      );
    });
  });
}
