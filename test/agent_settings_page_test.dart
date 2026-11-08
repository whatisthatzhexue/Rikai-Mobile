import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/settings/agent_settings_page.dart';
import 'package:rikai_mobile/services/agent/agent_provider_tester.dart';
import 'package:rikai_mobile/services/agent/ports/llm_port.dart';
import 'package:rikai_mobile/services/agent/ports/secret_port.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TesterSecret implements SecretPort {
  @override
  Future<String?> read(String key) async => '';

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _TesterLlm implements LlmPort {
  @override
  Stream<LlmEvent> stream(
    LlmRequest request, {
    LlmCancelToken? cancellation,
  }) async* {
    yield const LlmEvent(type: LlmEventType.textDelta, text: 'OK');
    yield LlmEvent.done();
  }
}

void main() {
  testWidgets('provider form uses Chinese labels and fills DeepSeek address', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型服务'), findsOneWidget);
    final autoAccept = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(autoAccept.value, isFalse);
    expect(find.text('生成词典档案时不再询问'), findsOneWidget);
    await tester.tap(find.text('添加模型服务'));
    await tester.pumpAndSettle();

    expect(find.text('服务商'), findsOneWidget);
    expect(find.text('接口地址'), findsOneWidget);
    expect(find.text('快速模型'), findsOneWidget);
    expect(find.text('高精度模型'), findsOneWidget);
    expect(find.text('最大输出 tokens（可选）'), findsOneWidget);
    expect(find.textContaining('OpenAI-compatible 建议留空'), findsOneWidget);
    expect(find.text('快速模型用于词典档案和资料检查。'), findsOneWidget);
    expect(find.text('高精度模型用于最终解析。'), findsOneWidget);
    expect(find.textContaining('API 的访问地址'), findsNothing);
    expect(find.textContaining('留空时回退'), findsNothing);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('Small model'), findsNothing);
    expect(find.text('Complex model'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('agent-provider-max-output-tokens')),
      '0',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入正整数，或留空使用默认'), findsOneWidget);

    final baseUrl = tester.widget<TextField>(
      find.byKey(const ValueKey('agent-provider-base-url')),
    );
    expect(baseUrl.controller?.text, 'https://api.deepseek.com/');

    await tester.enterText(
      find.byKey(const ValueKey('agent-provider-base-url')),
      'https://example.com/v1',
    );
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude（Anthropic）').last);
    await tester.pumpAndSettle();
    expect(baseUrl.controller?.text, 'https://example.com/v1');
  });

  testWidgets('provider dialog tests the connection without saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final testerService = AgentProviderTester(
      secrets: _TesterSecret(),
      llmFactory: (config, secrets) => _TesterLlm(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
          agentProviderTesterProvider.overrideWithValue(testerService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加模型服务'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-provider-small-model')),
      'deepseek-chat',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-provider-api-key')),
      'form-key',
    );
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('连接成功'), findsOneWidget);
    expect(find.textContaining('deepseek-chat'), findsWidgets);
    // Testing must not close the dialog or persist a provider.
    expect(find.byType(AlertDialog), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentSettingsPage)),
    );
    expect(container.read(agentProvidersProvider).asData?.value, isEmpty);
  });

  testWidgets('profile language changes immediately without a dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentSettingsPage)),
    );
    expect(container.read(appSettingsProvider).agentProfileLanguage, 'en');
  });

  testWidgets(
    'provider row shows address and model summaries on separate lines',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      const provider = AgentProviderConfig(
        id: 'p1',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/',
        smallModel: 'deepseek-chat',
        complexModel: 'deepseek-reasoner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProvidersProvider.overrideWith((ref) async => [provider]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AgentSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('接口地址：https://api.deepseek.com/'), findsOneWidget);
      expect(find.text('复杂模型：deepseek-reasoner'), findsOneWidget);
      expect(find.text('简单模型：deepseek-chat'), findsOneWidget);
    },
  );
}
