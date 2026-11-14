import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_profile.dart';
import 'package:lexicandy/services/agent/agent_intent.dart';

void main() {
  test('detects translation and grammar hints without a model call', () {
    final hint = detectAgentIntent('请翻译这句话并解释语法');

    expect(hint.tasks, containsAll(<String>['translation', 'grammar']));
    expect(hint.multipleTasks, isTrue);
    final prompt = hint.toPrompt(AgentResponseLanguage.chinese);
    expect(prompt, contains('translation, grammar'));
    expect(prompt, contains('output language: zh'));
    expect(prompt, contains('multiple tasks/questions: yes'));
  });

  test('detects English and Japanese keywords', () {
    expect(
      detectAgentIntent('Please translate and explain the grammar.').tasks,
      containsAll(<String>['translation', 'grammar', 'explanation']),
    );
    expect(
      detectAgentIntent('この文の読みと意味を教えて').tasks,
      containsAll(<String>['reading', 'explanation']),
    );
  });

  test('keeps a general hint when no task keyword is present', () {
    final hint = detectAgentIntent('この文をどう見ればいい？');

    expect(hint.tasks, isEmpty);
    expect(hint.multipleTasks, isFalse);
    expect(
      hint.toPrompt(AgentResponseLanguage.japanese),
      contains('general reading/explanation'),
    );
  });

  test('two question marks set the multi-task flag', () {
    final hint = detectAgentIntent('什么意思？怎么读？');

    expect(hint.multipleTasks, isTrue);
    expect(hint.tasks, containsAll(<String>['explanation', 'reading']));
  });
}
