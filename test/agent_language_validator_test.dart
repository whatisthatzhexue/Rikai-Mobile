import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_analysis.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/services/agent/agent_language_validator.dart';

AgentAnalysis _analysis({
  required String translation,
  required String meaning,
  String sense = '请务必',
  String grammar = '表示正式请求',
  String unresolved = '',
}) {
  return AgentAnalysis(
    sourceId: 'src-1',
    translation: <AgentTranslation>[
      AgentTranslation(quoteId: 'q1', text: translation),
    ],
    segments: <AgentSegment>[
      AgentSegment(
        id: 'seg-1',
        quoteId: 'q1',
        interpretation: meaning,
        epistemic: AgentEpistemic.dictionaryFact,
        wordNotes: <AgentWordNote>[
          AgentWordNote(
            tokenId: 't1',
            surface: '何卒',
            sense: sense,
            citationIds: const <String>['source-1'],
          ),
        ],
        grammarNotes: <AgentGrammarNote>[
          AgentGrammarNote(
            patternId: 'p1',
            explanation: grammar,
            citationIds: const <String>['source-1'],
          ),
        ],
      ),
    ],
    unresolved: unresolved.isEmpty
        ? const <AgentUnresolved>[]
        : <AgentUnresolved>[AgentUnresolved(quoteId: 'q1', reason: unresolved)],
  );
}

const _validator = AgentLanguageValidator();

void main() {
  test('accepts Chinese fields and ignores readings in parentheses', () {
    final check = _validator.check(
      _analysis(translation: '请多关照。', meaning: '用于正式请求对方关照的固定表达（なにとぞ）。'),
      AgentResponseLanguage.chinese,
    );
    expect(check.isMismatch, isFalse);
  });

  test('rejects Japanese prose for a Chinese target', () {
    final check = _validator.check(
      _analysis(translation: 'どういたしまして。', meaning: '正式な依頼です'),
      AgentResponseLanguage.chinese,
    );
    expect(check.isMismatch, isTrue);
    expect(check.mismatchedFields, contains('translation:q1'));
    expect(check.mismatchedFields, contains('segment:seg-1'));
  });

  test('rejects English prose for a Chinese target', () {
    final check = _validator.check(
      _analysis(
        translation: 'This is a formal request.',
        meaning: 'A fixed expression used for a request.',
      ),
      AgentResponseLanguage.chinese,
    );
    expect(check.isMismatch, isTrue);
  });

  test('rejects Japanese and Chinese prose for an English target', () {
    final japanese = _validator.check(
      _analysis(translation: 'どういたしまして。', meaning: '正式な依頼です'),
      AgentResponseLanguage.english,
    );
    expect(japanese.isMismatch, isTrue);

    final chinese = _validator.check(
      _analysis(translation: '请多关照。', meaning: '正式请求'),
      AgentResponseLanguage.english,
    );
    expect(chinese.isMismatch, isTrue);
  });

  test('rejects English prose for a Japanese target', () {
    final check = _validator.check(
      _analysis(
        translation: 'Please treat me well.',
        meaning: 'A formal request expression.',
      ),
      AgentResponseLanguage.japanese,
    );
    expect(check.isMismatch, isTrue);
  });

  test('strips allowed Japanese terms before judging a Chinese field', () {
    final check = _validator.check(
      _analysis(translation: '请多关照。', meaning: 'てしまう表示遗憾', grammar: 'てしまう表示遗憾'),
      AgentResponseLanguage.chinese,
      allowedJapaneseTerms: const <String>['てしまう'],
    );
    expect(check.mismatchedFields, isNot(contains('grammar:p1')));
  });
}
