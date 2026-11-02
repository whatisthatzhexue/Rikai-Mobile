import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/services/agent/agent_messages.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/agent_prompts.dart';
import 'package:rikai_mobile/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'default output language is Chinese and legacy follow migrates to zh',
    () {
      expect(
        AgentResponseLanguage.fromWire(null),
        AgentResponseLanguage.chinese,
      );
      expect(
        AgentResponseLanguage.fromWire('follow'),
        AgentResponseLanguage.chinese,
      );
      expect(
        AgentResponseLanguage.fromWire('en'),
        AgentResponseLanguage.english,
      );
      expect(
        AgentResponseLanguage.values.where(
          (value) => value.wireName == 'follow',
        ),
        isEmpty,
      );
      expect(const AppSettings().agentResponseLanguage, 'zh');
    },
  );

  test('settings store migrates a stored follow value to zh', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'agent_response_language': 'follow',
    });
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsStore(preferences).load();
    expect(settings.agentResponseLanguage, 'zh');
  });

  test('UI language comes only from the explicit setting', () {
    expect(
      resolveAgentUiLanguage(AgentResponseLanguage.chinese),
      AgentUiLanguage.chinese,
    );
    expect(
      resolveAgentUiLanguage(AgentResponseLanguage.english),
      AgentUiLanguage.english,
    );
    expect(
      resolveAgentUiLanguage(AgentResponseLanguage.japanese),
      AgentUiLanguage.japanese,
    );
    // The signature no longer accepts source text, so Japanese input cannot
    // flip the UI language.
    expect(AgentUiStrings.of(AgentUiLanguage.chinese).appTitle, '词典助手');
    expect(
      AgentUiStrings.of(AgentUiLanguage.english).appTitle,
      'Dictionary Assistant',
    );
    expect(
      agentStageMessage(AgentStage.tokenizing, AgentUiLanguage.chinese),
      '分词与检索依据',
    );
    expect(
      agentStageMessage(AgentStage.tokenizing, AgentUiLanguage.english),
      'Tokenizing and retrieving evidence',
    );
  });

  test(
    'prompt contract requires the configured language for readable fields',
    () {
      final prompt = analysisSystemPrompt(
        AgentMode.strict,
        AgentResponseLanguage.chinese,
      );
      expect(prompt, contains('Simplified Chinese'));
      expect(prompt, contains('word forms, readings and dictionary examples'));
      expect(prompt, isNot(contains('same language as the user request')));
    },
  );
}
